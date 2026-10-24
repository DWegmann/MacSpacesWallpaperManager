import Foundation

public struct WallpaperFolder: Equatable, Sendable {
    public let path: String
    public let bookmark: Data
    public init(path: String, bookmark: Data) { self.path = path; self.bookmark = bookmark }
}

/// Only explicitly supplied fields are shared. Unselected Spaces and per-Space image choices stay intact.
public struct SpaceRuleChanges: Sendable {
    public var folder: WallpaperFolder?
    public var recursive: Bool?
    public var rotation: RotationMode?
    public var layout: ImageLayout?
    public var backgroundColor: WallpaperColor?
    public var shuffle: Bool?
    public var enabled: Bool?

    public init() {}

    public var isEmpty: Bool {
        folder == nil && recursive == nil && rotation == nil && layout == nil
            && backgroundColor == nil && shuffle == nil && enabled == nil
    }

    public func applying(to original: SpaceRule) -> SpaceRule {
        var rule = original
        if let folder {
            rule.folderPath = folder.path
            rule.folderBookmark = folder.bookmark
            rule.selectedImagePath = nil
            rule.lastAppliedImagePath = nil
            rule.lastAppliedLayout = nil
            rule.lastAppliedBackgroundColor = nil
            rule.lastAppliedWithDirectMode = nil
            rule.lastAppliedAt = nil
        }
        if let recursive { rule.recursive = recursive }
        if let rotation { rule.rotation = rotation }
        if let layout { rule.layout = layout }
        if let backgroundColor { rule.backgroundColor = backgroundColor }
        if let shuffle { rule.shuffle = shuffle }
        if let enabled { rule.enabled = enabled }
        return rule
    }

    public func applying(to rules: [String: SpaceRule], spaceIDs: Set<String>) -> [String: SpaceRule] {
        guard !isEmpty, !spaceIDs.isEmpty else { return rules }
        var result = rules
        for id in spaceIDs { result[id] = applying(to: rules[id] ?? SpaceRule()) }
        return result
    }
}
