import AppKit
import CoreGraphics
import Darwin

public enum SpaceCatalogError: LocalizedError {
    case unavailable
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Die Space-Erkennung ist auf dieser macOS-Version nicht verfügbar. Es werden keine Hintergrundbilder geändert."
        case .invalidData:
            return "macOS hat keine erkennbaren Desktop-Spaces geliefert. Bitte aktualisiere die Liste erneut."
        }
    }
}

public enum SpaceParser {
    /// Kept separate from the private bridge so macOS data variants can be tested without changing desktops.
    public static func parse(_ managedDisplays: [[String: Any]], screens: [ScreenIdentity],
                             separateSpaces: Bool) -> [DesktopSpace] {
        var result: [DesktopSpace] = []
        for screen in screens {
            guard let display = managedDisplays.first(where: {
                guard let identifier = $0["Display Identifier"] as? String else { return false }
                return separateSpaces ? identifier.caseInsensitiveCompare(screen.id) == .orderedSame : identifier == "Main"
            }), let spaces = display["Spaces"] as? [[String: Any]] else { continue }
            let current = display["Current Space"] as? [String: Any]
            let currentID = current.flatMap(runtimeID)
            var number = 0
            for space in spaces {
                guard (space["type"] as? NSNumber)?.intValue == 0,
                      let uuid = space["uuid"] as? String, !uuid.isEmpty,
                      let spaceID = runtimeID(space) else { continue }
                number += 1
                result.append(DesktopSpace(uuid: uuid, runtimeID: spaceID, display: screen,
                                           number: number, isVisible: currentID == spaceID))
            }
        }
        return result
    }

    private static func runtimeID(_ space: [String: Any]) -> UInt64? {
        (space["ManagedSpaceID"] as? NSNumber)?.uint64Value ?? (space["id64"] as? NSNumber)?.uint64Value
    }
}

/// Apple has no public API for enumerating Spaces. These two optional SkyLight symbols only read state.
/// Wallpaper writes are handled separately by NSWorkspace or the optional direct-store backend.
@MainActor
public final class SpaceCatalog {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CopyManagedSpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private let handle: UnsafeMutableRawPointer?

    public init() {
        handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY | RTLD_LOCAL)
    }

    deinit { if let handle { dlclose(handle) } }

    public func read() throws -> [DesktopSpace] {
        guard let handle,
              let connectionSymbol = dlsym(handle, "SLSMainConnectionID") ?? dlsym(handle, "CGSMainConnectionID"),
              let spacesSymbol = dlsym(handle, "SLSCopyManagedDisplaySpaces") ?? dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { throw SpaceCatalogError.unavailable }
        let connection = unsafeBitCast(connectionSymbol, to: MainConnection.self)
        let copy = unsafeBitCast(spacesSymbol, to: CopyManagedSpaces.self)
        guard let raw = copy(connection())?.takeRetainedValue(),
              let displays = raw as NSArray as? [[String: Any]] else { throw SpaceCatalogError.invalidData }
        let screens = NSScreen.screens.compactMap { screen -> ScreenIdentity? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
            return ScreenIdentity(id: CFUUIDCreateString(nil, uuid) as String, name: screen.localizedName,
                                  displayID: number.uint32Value)
        }
        let spaces = SpaceParser.parse(displays, screens: screens, separateSpaces: NSScreen.screensHaveSeparateSpaces)
        guard !spaces.isEmpty else { throw SpaceCatalogError.invalidData }
        return spaces
    }
}
