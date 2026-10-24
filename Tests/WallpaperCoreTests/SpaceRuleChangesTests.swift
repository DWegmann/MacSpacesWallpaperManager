import Foundation
import XCTest
@testable import WallpaperCore

final class SpaceRuleChangesTests: XCTestCase {
    func testOnlySelectedFieldsAndSpacesAreChanged() {
        var first = SpaceRule()
        first.folderPath = "/Bilder/Erster"
        first.folderBookmark = Data([1])
        first.selectedImagePath = "/Bilder/Erster/See.jpg"
        first.lastAppliedImagePath = first.selectedImagePath
        first.recursive = false
        var second = SpaceRule()
        second.folderPath = "/Bilder/Zweiter"
        second.selectedImagePath = "/Bilder/Zweiter/Berg.jpg"
        second.shuffle = false
        let original = ["first": first, "second": second, "untouched": first]
        var changes = SpaceRuleChanges()
        changes.layout = .fit
        changes.backgroundColor = WallpaperColor(red: 0.2, green: 0.4, blue: 0.6)
        changes.rotation = .hourly
        let result = changes.applying(to: original, spaceIDs: ["first", "second"])
        XCTAssertEqual(result["untouched"], first)
        XCTAssertEqual(result["first"]?.folderBookmark, first.folderBookmark)
        XCTAssertEqual(result["first"]?.selectedImagePath, first.selectedImagePath)
        XCTAssertEqual(result["second"]?.folderPath, second.folderPath)
        XCTAssertEqual(result["second"]?.selectedImagePath, second.selectedImagePath)
        XCTAssertEqual(result["first"]?.recursive, false)
        XCTAssertEqual(result["second"]?.shuffle, false)
        for id in ["first", "second"] {
            XCTAssertEqual(result[id]?.layout, .fit)
            XCTAssertEqual(result[id]?.backgroundColor, changes.backgroundColor)
            XCTAssertEqual(result[id]?.rotation, .hourly)
        }
    }

    func testCommonFolderResetsImageStateButPreservesUncheckedActivationAndColor() {
        var rule = SpaceRule()
        rule.enabled = false
        rule.folderPath = "/old"
        rule.selectedImagePath = "/old/image.png"
        rule.lastAppliedImagePath = rule.selectedImagePath
        rule.lastAppliedAt = Date()
        rule.lastAppliedLayout = .fit
        rule.lastAppliedWithDirectMode = true
        rule.backgroundColor = WallpaperColor(red: 0.3, green: 0.4, blue: 0.5)
        rule.lastAppliedBackgroundColor = rule.backgroundColor
        var changes = SpaceRuleChanges()
        changes.folder = WallpaperFolder(path: "/new", bookmark: Data([2, 3]))
        changes.recursive = true
        let result = changes.applying(to: rule)
        XCTAssertEqual(result.folderPath, "/new")
        XCTAssertEqual(result.folderBookmark, Data([2, 3]))
        XCTAssertTrue(result.recursive)
        XCTAssertFalse(result.enabled)
        XCTAssertEqual(result.backgroundColor, rule.backgroundColor)
        XCTAssertNil(result.selectedImagePath)
        XCTAssertNil(result.lastAppliedImagePath)
        XCTAssertNil(result.lastAppliedAt)
        XCTAssertNil(result.lastAppliedLayout)
        XCTAssertNil(result.lastAppliedWithDirectMode)
        XCTAssertNil(result.lastAppliedBackgroundColor)
    }

    func testExplicitFalseValuesAreAppliedAndNewRulesCanBePrepared() {
        var changes = SpaceRuleChanges()
        changes.recursive = false
        changes.shuffle = false
        changes.enabled = false
        let result = changes.applying(to: [:], spaceIDs: ["new"])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["new"]?.recursive, false)
        XCTAssertEqual(result["new"]?.shuffle, false)
        XCTAssertEqual(result["new"]?.enabled, false)
        XCTAssertNil(result["new"]?.folderPath)
    }

    func testNoSelectionOrNoCheckedSettingsDoesNotCreateOrModifyRules() {
        let original = ["first": SpaceRule()]
        var changes = SpaceRuleChanges()
        XCTAssertEqual(changes.applying(to: original, spaceIDs: ["new"]), original)
        changes.layout = .fit
        XCTAssertEqual(changes.applying(to: original, spaceIDs: []), original)
    }
}

final class WallpaperColorTests: XCTestCase {
    func testColorIsPersistedAndOnlyUsedForFitLayout() throws {
        var rule = SpaceRule()
        rule.backgroundColor = WallpaperColor(red: 0.1, green: 0.2, blue: 0.3)
        XCTAssertEqual(rule.effectiveBackgroundColor, .black)
        rule.layout = .fit
        XCTAssertEqual(rule.effectiveBackgroundColor, rule.backgroundColor)
        XCTAssertEqual(try JSONDecoder().decode(SpaceRule.self, from: JSONEncoder().encode(rule)), rule)
        rule.layout = .center
        XCTAssertEqual(rule.effectiveBackgroundColor, .black)
        XCTAssertEqual(rule.resolvedBackgroundColor, rule.backgroundColor)
    }

    func testExistingRulesWithoutColorDefaultToBlack() throws {
        let encoded = try JSONEncoder().encode(SpaceRule())
        var object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        object.removeValue(forKey: "backgroundColor")
        object.removeValue(forKey: "lastAppliedBackgroundColor")
        let data = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(SpaceRule.self, from: data)
        XCTAssertEqual(decoded.resolvedBackgroundColor, .black)
        XCTAssertNil(decoded.lastAppliedBackgroundColor)
    }

    func testOutOfRangeAndNonfiniteChannelsAreNormalized() throws {
        XCTAssertEqual(WallpaperColor(red: -1, green: 2, blue: .nan), WallpaperColor(red: 0, green: 1, blue: 0))
        let decoded = try JSONDecoder().decode(WallpaperColor.self, from: Data("{\"red\":-3,\"green\":5,\"blue\":0.4}".utf8))
        XCTAssertEqual(decoded, WallpaperColor(red: 0, green: 1, blue: 0.4))
    }
}
