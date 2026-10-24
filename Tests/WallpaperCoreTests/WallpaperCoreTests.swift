import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import WallpaperCore

final class ImageScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesWallpaperManagerTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testRecursionNaturalSortingAndInvalidFiles() throws {
        try writePNG("image10.png")
        try writePNG("image2.png")
        try writePNG("Nested/deeper/image.png")
        try writePNG(".hidden.png")
        try writePNG(".hiddenFolder/inside.png")
        try writePNG("Ignored.app/Contents/inside.png")
        try Data("not a picture".utf8).write(to: root.appendingPathComponent("broken.png"))
        try Data("text".utf8).write(to: root.appendingPathComponent("notes.txt"))

        let shallow = try ImageScanner.scan(folder: root, recursive: false)
        XCTAssertEqual(shallow.images.map(\.lastPathComponent), ["image2.png", "image10.png"])
        XCTAssertEqual(shallow.skippedCount, 1)
        let recursive = try ImageScanner.scan(folder: root, recursive: true)
        XCTAssertEqual(recursive.images.count, 3)
        XCTAssertTrue(recursive.images.contains { $0.lastPathComponent == "image.png" })
        XCTAssertFalse(recursive.images.contains { $0.path.contains("Ignored.app") || $0.path.contains(".hidden") })
    }

    func testSymlinkCyclesAndLinkedFilesAreExcluded() throws {
        try writePNG("real.png")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("cycle"), withDestinationURL: root)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.png"), withDestinationURL: root.appendingPathComponent("real.png"))
        let result = try ImageScanner.scan(folder: root, recursive: true)
        XCTAssertEqual(result.images.map(\.lastPathComponent), ["real.png"])
    }

    func testMissingFolderFailsInsteadOfReturningEmptyLibrary() {
        XCTAssertThrowsError(try ImageScanner.scan(folder: root.appendingPathComponent("missing"), recursive: true))
    }

    func testCancelledScanStops() async throws {
        try writePNG("image.png")
        let directory = root!
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try ImageScanner.scan(folder: directory, recursive: true)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled scan should throw")
        } catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

    private func writePNG(_ relativePath: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.4, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}

final class SpaceParserTests: XCTestCase {
    private let first = ScreenIdentity(id: "SCREEN-A", name: "Built-in", displayID: 1)
    private let second = ScreenIdentity(id: "SCREEN-B", name: "External", displayID: 2)

    func testSeparateDisplaysAndFullscreenFiltering() {
        let spaces = SpaceParser.parse([
            display("screen-a", current: 9, spaces: [space(8, uuid: "one"), space(99, uuid: "fullscreen", type: 4), space(9, uuid: "two")]),
            display("SCREEN-B", current: 20, spaces: [space(20, uuid: "three")])
        ], screens: [first, second], separateSpaces: true)
        XCTAssertEqual(spaces.count, 3)
        XCTAssertEqual(spaces.map(\.number), [1, 2, 1])
        XCTAssertEqual(spaces.map(\.isVisible), [false, true, true])
        XCTAssertEqual(spaces[1].id, "screen-a/two")
    }

    func testSharedSpacesStillHaveSeparateDisplayRules() {
        let spaces = SpaceParser.parse([
            display("Main", current: 8, spaces: [space(8, uuid: "one"), space(9, uuid: "two")])
        ], screens: [first, second], separateSpaces: false)
        XCTAssertEqual(spaces.count, 4)
        XCTAssertEqual(Set(spaces.map(\.id)).count, 4)
        XCTAssertEqual(spaces.filter(\.isVisible).count, 2)
    }

    func testStableIdentitySurvivesReorderingAndRuntimeIDChanges() {
        let before = SpaceParser.parse([display("SCREEN-A", current: 8, spaces: [space(8, uuid: "one"), space(9, uuid: "two")])], screens: [first], separateSpaces: true)
        let after = SpaceParser.parse([display("SCREEN-A", current: 31, spaces: [space(30, uuid: "two"), space(31, uuid: "one")])], screens: [first], separateSpaces: true)
        XCTAssertEqual(before[0].id, after[1].id)
        XCTAssertNotEqual(before[0].number, after[1].number)
    }

    func testMalformedDataIsNotGuessed() {
        XCTAssertTrue(SpaceParser.parse([["Spaces": [space(1, uuid: "one")]]], screens: [first], separateSpaces: true).isEmpty)
        XCTAssertTrue(SpaceParser.parse([display("SCREEN-A", current: 1, spaces: [["id64": 1, "type": 0]])], screens: [first], separateSpaces: true).isEmpty)
    }

    func testId64FallbackAndFullscreenCurrentSpace() {
        let data: [[String: Any]] = [["Display Identifier": "SCREEN-A", "Current Space": ["id64": 99],
                                    "Spaces": [["id64": 8, "uuid": "one", "type": 0], space(99, uuid: "full", type: 4)]]]
        let spaces = SpaceParser.parse(data, screens: [first], separateSpaces: true)
        XCTAssertEqual(spaces.count, 1)
        XCTAssertFalse(spaces[0].isVisible)
    }

    private func space(_ id: Int, uuid: String, type: Int = 0) -> [String: Any] {
        ["ManagedSpaceID": id, "uuid": uuid, "type": type]
    }
    private func display(_ id: String, current: Int, spaces: [[String: Any]]) -> [String: Any] {
        ["Display Identifier": id, "Current Space": ["ManagedSpaceID": current], "Spaces": spaces]
    }
}

final class ImageSelectionTests: XCTestCase {
    private let images = (1...3).map { URL(fileURLWithPath: "/wallpapers/\($0).jpg") }

    func testEmptyAndSingleImageLibrary() {
        XCTAssertNil(ImageSelection.next(in: [], after: nil, shuffle: true))
        XCTAssertEqual(ImageSelection.next(in: [images[0]], after: images[0].path, shuffle: true), images[0])
    }

    func testOrderedSelectionWrapsAndRecoversFromRemovedImage() {
        XCTAssertEqual(ImageSelection.next(in: images, after: images[0].path, shuffle: false), images[1])
        XCTAssertEqual(ImageSelection.next(in: images, after: images[2].path, shuffle: false), images[0])
        XCTAssertEqual(ImageSelection.next(in: images, after: "/deleted.jpg", shuffle: false), images[0])
    }

    func testShuffleNeverImmediatelyRepeats() {
        for previous in images {
            for index in 0..<2 {
                XCTAssertNotEqual(ImageSelection.next(in: images, after: previous.path, shuffle: true, randomIndex: { _ in index }), previous)
            }
        }
    }

    func testIntervalsRespectExactBoundaryAndManualMode() {
        let now = Date(timeIntervalSince1970: 10_000)
        var rule = SpaceRule()
        rule.rotation = .everyFiveMinutes
        rule.lastAppliedAt = now.addingTimeInterval(-299)
        XCTAssertFalse(ImageSelection.isDue(rule: rule, now: now))
        rule.lastAppliedAt = now.addingTimeInterval(-300)
        XCTAssertTrue(ImageSelection.isDue(rule: rule, now: now))
        rule.rotation = .manual
        XCTAssertFalse(ImageSelection.isDue(rule: rule, now: now))
        rule.rotation = .onSpaceChange
        XCTAssertFalse(ImageSelection.isDue(rule: rule, now: now))
        rule.rotation = .hourly
        rule.lastAppliedAt = nil
        XCTAssertTrue(ImageSelection.isDue(rule: rule, now: now))
    }
}

final class ConfigurationStoreTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesWallpaperManagerStoreTests-\(UUID())")
    }
    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
    }

    func testMissingConfigurationAndRoundTrip() throws {
        let store = ConfigurationStore(url: root.appendingPathComponent("settings.json"))
        XCTAssertEqual(try store.load(), AppConfiguration())
        var configuration = AppConfiguration()
        var rule = SpaceRule()
        rule.folderPath = "/Bilder/Grüne Berge"
        rule.folderBookmark = Data([1, 2, 3])
        rule.recursive = false
        rule.rotation = .everyThirtyMinutes
        rule.selectedImagePath = "/Bilder/Grüne Berge/See.png"
        configuration.rules["display/space"] = rule
        configuration.paused = true
        try store.save(configuration)
        XCTAssertEqual(try store.load(), configuration)
        configuration.paused = false
        try store.save(configuration)
        XCTAssertEqual(try store.load(), configuration)
    }

    func testCorruptOrFutureConfigurationIsPreserved() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("settings.json")
        let store = ConfigurationStore(url: url)
        for contents in ["invalid json", "{\"schemaVersion\":99,\"paused\":false,\"rules\":{}}"] {
            let data = Data(contents.utf8)
            try data.write(to: url)
            XCTAssertThrowsError(try store.load())
            XCTAssertEqual(try Data(contentsOf: url), data)
        }
    }
}
