import Foundation

public enum ImageLayout: String, Codable, CaseIterable, Sendable {
    case fill, fit, stretch, center

    public var title: String {
        switch self {
        case .fill: return "Bildschirmfüllend"
        case .fit: return "An Bildschirm anpassen"
        case .stretch: return "Dehnen"
        case .center: return "Zentrieren"
        }
    }
}

public enum RotationMode: String, Codable, CaseIterable, Sendable {
    case manual, onSpaceChange, everyFiveMinutes, everyFifteenMinutes, everyThirtyMinutes, hourly, daily

    public var title: String {
        switch self {
        case .manual: return "Manuell"
        case .onSpaceChange: return "Bei jedem Space-Wechsel"
        case .everyFiveMinutes: return "Alle 5 Minuten"
        case .everyFifteenMinutes: return "Alle 15 Minuten"
        case .everyThirtyMinutes: return "Alle 30 Minuten"
        case .hourly: return "Jede Stunde"
        case .daily: return "Jeden Tag"
        }
    }

    public var interval: TimeInterval? {
        switch self {
        case .manual, .onSpaceChange: return nil
        case .everyFiveMinutes: return 300
        case .everyFifteenMinutes: return 900
        case .everyThirtyMinutes: return 1_800
        case .hourly: return 3_600
        case .daily: return 86_400
        }
    }
}

public struct SpaceRule: Codable, Equatable, Sendable {
    public var folderBookmark: Data?
    public var folderPath: String?
    public var recursive = true
    public var enabled = true
    public var shuffle = true
    public var layout: ImageLayout = .fill
    public var backgroundColor: WallpaperColor?
    public var rotation: RotationMode = .manual
    public var selectedImagePath: String?
    public var lastAppliedImagePath: String?
    public var lastAppliedLayout: ImageLayout?
    public var lastAppliedBackgroundColor: WallpaperColor?
    public var lastAppliedWithDirectMode: Bool?
    public var lastAppliedAt: Date?

    public init() {}

    public var resolvedBackgroundColor: WallpaperColor { backgroundColor ?? .black }
    public var effectiveBackgroundColor: WallpaperColor { layout == .fit ? resolvedBackgroundColor : .black }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var paused = false
    public var rules: [String: SpaceRule] = [:]
    public var directWallpaperMode = false

    public init() {}

    private enum CodingKeys: String, CodingKey { case schemaVersion, paused, rules, directWallpaperMode }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        paused = try values.decode(Bool.self, forKey: .paused)
        rules = try values.decode([String: SpaceRule].self, forKey: .rules)
        directWallpaperMode = try values.decodeIfPresent(Bool.self, forKey: .directWallpaperMode) ?? false
    }
}

public struct ScreenIdentity: Equatable, Sendable {
    public let id: String
    public let name: String
    public let displayID: UInt32

    public init(id: String, name: String, displayID: UInt32) {
        self.id = id
        self.name = name
        self.displayID = displayID
    }
}

public struct DesktopSpace: Identifiable, Equatable, Sendable {
    public let id: String
    public let uuid: String
    public let runtimeID: UInt64
    public let display: ScreenIdentity
    public let number: Int
    public let isVisible: Bool

    public var title: String { "Desktop \(number)" }

    public init(uuid: String, runtimeID: UInt64, display: ScreenIdentity, number: Int, isVisible: Bool) {
        self.uuid = uuid
        self.id = display.id.lowercased() + "/" + uuid.lowercased()
        self.runtimeID = runtimeID
        self.display = display
        self.number = number
        self.isVisible = isVisible
    }
}

public enum ImageSelection {
    /// The caller supplies the random index so selection is deterministic in tests.
    public static func next(in images: [URL], after previousPath: String?, shuffle: Bool,
                            randomIndex: (Int) -> Int = { Int.random(in: 0..<$0) }) -> URL? {
        guard !images.isEmpty else { return nil }
        if shuffle {
            let candidates = images.count > 1 ? images.filter { $0.path != previousPath } : images
            return candidates[randomIndex(candidates.count)]
        }
        guard let previousPath, let index = images.firstIndex(where: { $0.path == previousPath }) else {
            return images[0]
        }
        return images[(index + 1) % images.count]
    }

    public static func isDue(rule: SpaceRule, now: Date) -> Bool {
        guard let interval = rule.rotation.interval else { return false }
        guard let lastAppliedAt = rule.lastAppliedAt else { return true }
        return now.timeIntervalSince(lastAppliedAt) >= interval
    }
}
