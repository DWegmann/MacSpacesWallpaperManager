import Foundation
import CoreGraphics

public struct DirectWallpaperChange: Sendable {
    public let spaceUUID: String
    public let displayUUID: String
    public let imageURL: URL
    public let layout: ImageLayout
    public let backgroundColor: WallpaperColor?

    public init(spaceUUID: String, displayUUID: String, imageURL: URL, layout: ImageLayout,
                backgroundColor: WallpaperColor? = nil) {
        self.spaceUUID = spaceUUID
        self.displayUUID = displayUUID
        self.imageURL = imageURL
        self.layout = layout
        self.backgroundColor = backgroundColor
    }
}

public enum DirectWallpaperError: LocalizedError {
    case unsupportedStore
    case globalWallpaper
    case missingSpace
    case linkedWallpaper
    case concurrentChange
    case busy
    case agentUnavailable
    case agentControlFailed
    case reloadFailed
    case noBackup
    case restoreConflict
    case invalidImage
    case transactionFailed(String, String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedStore: return "Direct mode does not support this macOS wallpaper store format."
        case .globalWallpaper: return "macOS is using a shared wallpaper for all Spaces. First turn off “Show on all Spaces” in Wallpaper settings."
        case .missingSpace: return "macOS has not saved an entry for a selected Space yet. Visit the Space once and try again."
        case .linkedWallpaper: return "A selected Space uses a linked wallpaper and screen saver. Choose a static image there first, or use standard mode."
        case .concurrentChange: return "The wallpaper settings were changed at the same time. Nothing was overwritten. Please try again."
        case .busy: return "Another instance of the app is currently changing wallpapers."
        case .agentUnavailable: return "The macOS wallpaper service could not be uniquely identified."
        case .agentControlFailed: return "The macOS wallpaper service could not be safely paused."
        case .reloadFailed: return "The macOS wallpaper service did not confirm the change."
        case .noBackup: return "No restorable direct-mode backup is available."
        case .restoreConflict: return "An affected wallpaper has since changed outside the app. Restoration was canceled to preserve that change."
        case .invalidImage: return "A selected image file is no longer readable or is not supported by macOS. Please rescan the image folder."
        case let .transactionFailed(reason, recovery): return "\(reason) \(recovery)"
        }
    }
}

public struct DirectWallpaperUndo: Codable, Sendable {
    let spaceKey: String
    let displayKey: String
    let previousEntry: Data?
    let writtenEntry: Data?
}

public struct DirectWallpaperPatch: Sendable {
    public let data: Data
    public let undo: [DirectWallpaperUndo]
}

/// Transforms a copy of Index.plist. Never writes, changes Spaces, or controls the wallpaper agent.
public enum DirectWallpaperStore {
    public static func patch(_ data: Data, changes: [DirectWallpaperChange], now: Date = Date()) throws -> DirectWallpaperPatch {
        var root = try decode(data)
        try validate(root)
        var spaces = root["Spaces"] as! [String: Any]
        var undo: [DirectWallpaperUndo] = []
        var seen = Set<String>()
        for change in changes {
            guard change.imageURL.isFileURL, !change.imageURL.path.isEmpty,
                  seen.insert(change.spaceUUID.lowercased() + "/" + change.displayUUID.lowercased()).inserted else {
                throw DirectWallpaperError.unsupportedStore
            }
            guard let spaceKey = key(change.spaceUUID, in: spaces),
                  var space = spaces[spaceKey] as? [String: Any],
                  var displays = space["Displays"] as? [String: Any] else { throw DirectWallpaperError.missingSpace }
            let displayKey = key(change.displayUUID, in: displays) ?? change.displayUUID.uppercased()
            if let value = displays[displayKey], !(value is [String: Any]) { throw DirectWallpaperError.unsupportedStore }
            let previous = displays[displayKey] as? [String: Any]
            // New display overrides inherit the existing Space default; other displays/defaults stay intact.
            guard var entry = previous ?? space["Default"] as? [String: Any],
                  let desktop = entry["Desktop"] as? [String: Any] else { throw DirectWallpaperError.unsupportedStore }
            guard entry["Type"] as? String == "individual" else { throw DirectWallpaperError.linkedWallpaper }
            let updated = try desktopEntry(desktop, change: change, now: now)
            if previous != nil && equalDesktop(desktop, updated) { continue }
            entry["Desktop"] = updated
            undo.append(DirectWallpaperUndo(spaceKey: spaceKey, displayKey: displayKey,
                                             previousEntry: try previous.map(encode), writtenEntry: try encode(entry)))
            displays[displayKey] = entry
            space["Displays"] = displays
            spaces[spaceKey] = space
        }
        root["Spaces"] = spaces
        return DirectWallpaperPatch(data: undo.isEmpty ? data : try encode(root), undo: undo)
    }

    /// Restores only owned Desktop leaves, retaining unrelated screensaver, display and Space edits.
    public static func restoring(_ data: Data, undo: [DirectWallpaperUndo]) throws -> Data {
        try restoration(data, undo: undo).data
    }

    static func restoration(_ data: Data, undo: [DirectWallpaperUndo]) throws -> DirectWallpaperPatch {
        var root = try decode(data)
        try validate(root)
        var spaces = root["Spaces"] as! [String: Any]
        var inverse: [DirectWallpaperUndo] = []
        for item in undo {
            guard var space = spaces[item.spaceKey] as? [String: Any],
                  var displays = space["Displays"] as? [String: Any] else { throw DirectWallpaperError.restoreConflict }
            let current = displays[item.displayKey] as? [String: Any]
            if displays[item.displayKey] != nil && current == nil { throw DirectWallpaperError.restoreConflict }
            let written = try item.writtenEntry.map(decode)
            guard matches(current, written) else { throw DirectWallpaperError.restoreConflict }
            var next: [String: Any]?
            if let previous = item.previousEntry {
                let original = try decode(previous)
                var restored = current ?? original
                restored["Desktop"] = original["Desktop"]
                next = restored
            } else {
                // Removing a newly created override must not erase a later screensaver/metadata change.
                var currentRemainder = current ?? [:]
                var writtenRemainder = written ?? [:]
                currentRemainder.removeValue(forKey: "Desktop")
                writtenRemainder.removeValue(forKey: "Desktop")
                guard equal(currentRemainder, writtenRemainder) else { throw DirectWallpaperError.restoreConflict }
            }
            inverse.append(DirectWallpaperUndo(spaceKey: item.spaceKey, displayKey: item.displayKey,
                                                previousEntry: try current.map(encode), writtenEntry: try next.map(encode)))
            displays[item.displayKey] = next
            space["Displays"] = displays
            spaces[item.spaceKey] = space
        }
        root["Spaces"] = spaces
        return DirectWallpaperPatch(data: try encode(root), undo: inverse)
    }

    public static func containsChanges(_ data: Data, undo: [DirectWallpaperUndo]) -> Bool {
        guard let root = try? decode(data), (try? validate(root)) != nil,
              let spaces = root["Spaces"] as? [String: Any] else { return false }
        return undo.allSatisfy { item in
            guard let space = spaces[item.spaceKey] as? [String: Any],
                  let displays = space["Displays"] as? [String: Any] else { return false }
            if let entry = displays[item.displayKey], !(entry is [String: Any]) { return false }
            do { return matches(displays[item.displayKey] as? [String: Any], try item.writtenEntry.map(decode)) }
            catch { return false }
        }
    }

    static func decode(_ data: Data) throws -> [String: Any] {
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw DirectWallpaperError.unsupportedStore
        }
        return root
    }

    static func encode(_ value: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
    }

    private static func validate(_ root: [String: Any]) throws {
        guard root["Spaces"] is [String: Any], root["Displays"] is [String: Any],
              root["SystemDefault"] is [String: Any] else { throw DirectWallpaperError.unsupportedStore }
        if let global = root["AllSpacesAndDisplays"], !(global is String && global as? String == "$null") {
            throw DirectWallpaperError.globalWallpaper
        }
    }

    private static func key(_ uuid: String, in dictionary: [String: Any]) -> String? {
        dictionary.keys.first { $0.caseInsensitiveCompare(uuid) == .orderedSame }
    }

    private static func desktopEntry(_ original: [String: Any], change: DirectWallpaperChange, now: Date) throws -> [String: Any] {
        guard var content = original["Content"] as? [String: Any], content["Choices"] is [[String: Any]] else {
            throw DirectWallpaperError.unsupportedStore
        }
        var options: [String: Any] = ["values": [String: Any]()]
        if let data = content["EncodedOptionValues"] as? Data { options = try decode(data) }
        else if let value = content["EncodedOptionValues"], value as? String != "$null" {
            throw DirectWallpaperError.unsupportedStore
        }
        guard var values = options["values"] as? [String: Any] else { throw DirectWallpaperError.unsupportedStore }
        let placement: String
        switch change.layout {
        case .fill: placement = "Crop"
        case .fit: placement = "SizeToFit"
        case .stretch: placement = "FillScreen"
        case .center: placement = "Centered"
        }
        values["placement"] = ["picker": ["_0": ["id": placement]]]
        if let color = change.backgroundColor, change.layout == .fit {
            let colorSpace = try PropertyListSerialization.data(fromPropertyList: CGColorSpace.sRGB as String,
                                                               format: .binary, options: 0)
            values["color"] = ["color": ["_0": ["color": [
                "components": [color.red, color.green, color.blue, 1.0], "colorSpace": colorSpace
            ]]]]
        }
        options["values"] = values
        content["EncodedOptionValues"] = try encode(options)
        content["Shuffle"] = "$null"
        content["Choices"] = [[
            "Provider": "com.apple.wallpaper.choice.image",
            "Files": [Any](),
            "Configuration": try encode(["type": "imageFile", "url": ["relative": change.imageURL.absoluteString]])
        ]]
        var result = original
        result["Content"] = content
        result["LastSet"] = now
        result["LastUse"] = now
        return result
    }

    private static func equalDesktop(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        var left = lhs
        var right = rhs
        for name in ["LastSet", "LastUse"] { left.removeValue(forKey: name); right.removeValue(forKey: name) }
        return equal(left, right)
    }

    private static func matches(_ current: [String: Any]?, _ written: [String: Any]?) -> Bool {
        guard let written else { return current == nil }
        guard let current, current["Type"] as? String == written["Type"] as? String,
              let desktop = current["Desktop"] as? [String: Any],
              let expected = written["Desktop"] as? [String: Any] else { return false }
        return equalDesktop(desktop, expected)
    }

    private static func equal(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: normalized(lhs) as! [String: Any]).isEqual(to: normalized(rhs) as! [String: Any])
    }

    private static func normalized(_ value: Any) -> Any {
        if let data = value as? Data,
           let inner = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) { return normalized(inner) }
        if let dictionary = value as? [String: Any] { return dictionary.mapValues(normalized) }
        if let array = value as? [Any] { return array.map(normalized) }
        return value
    }
}
