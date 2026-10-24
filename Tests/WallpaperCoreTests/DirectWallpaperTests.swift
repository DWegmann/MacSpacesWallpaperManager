import Darwin
import Foundation
import ImageIO
import CoreGraphics
import XCTest
@testable import WallpaperCore

private enum StoreFixture {
    static let firstSpace = "11111111-1111-1111-1111-111111111111"
    static let secondSpace = "22222222-2222-2222-2222-222222222222"
    static let firstDisplay = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    static let secondDisplay = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"

    static func entry(_ name: String) throws -> [String: Any] {
        ["Type": "individual", "UnrelatedEntryField": name,
         "Idle": ["ScreenSaver": name],
         "Desktop": ["LastUse": Date(timeIntervalSince1970: 100), "CustomMetadata": "keep",
                     "Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.image", "Files": [Any](),
                                              "Configuration": try DirectWallpaperStore.encode(["type": "imageFile", "url": ["relative": "file:///old/\(name).png"]])]],
                                 "Shuffle": "$null", "UnknownContentField": "keep",
                                 "EncodedOptionValues": try DirectWallpaperStore.encode(["values": [
                                    "placement": ["picker": ["_0": ["id": "SizeToFit"]]],
                                    "color": ["existing": "preserve"]
                                 ]])]]]
    }

    static func root() throws -> [String: Any] {
        ["AllSpacesAndDisplays": "$null", "SystemDefault": try entry("system"),
         "Displays": [firstDisplay: try entry("display-a"), secondDisplay: try entry("display-b")],
         "FutureTopLevelField": ["preserve": true],
         "Spaces": [firstSpace: ["Default": try entry("space-a"),
                                 "Displays": [firstDisplay: try entry("a-a"), secondDisplay: try entry("a-b")]],
                    secondSpace: ["Default": try entry("space-b"),
                                  "Displays": [firstDisplay: try entry("b-a"), secondDisplay: try entry("b-b")]]]]
    }

    static func target(_ root: [String: Any], space: String = secondSpace, display: String = firstDisplay) -> [String: Any] {
        ((root["Spaces"] as! [String: Any])[space] as! [String: Any])["Displays"]
            .flatMap { ($0 as? [String: Any])?[display] as? [String: Any] } ?? [:]
    }

    static func replace(_ root: inout [String: Any], space: String = secondSpace, display: String = firstDisplay,
                        edit: (inout [String: Any]) -> Void) {
        var spaces = root["Spaces"] as! [String: Any]
        var item = spaces[space] as! [String: Any]
        var displays = item["Displays"] as! [String: Any]
        var entry = displays[display] as! [String: Any]
        edit(&entry)
        displays[display] = entry
        item["Displays"] = displays
        spaces[space] = item
        root["Spaces"] = spaces
    }

    static func change(_ image: URL, display: String = firstDisplay, layout: ImageLayout = .fill) -> DirectWallpaperChange {
        DirectWallpaperChange(spaceUUID: secondSpace, displayUUID: display.lowercased(), imageURL: image, layout: layout)
    }
}

final class DirectWallpaperStoreTests: XCTestCase {
    private let image = URL(fileURLWithPath: "/Bilder/Grüne Berge/See #1.png")

    func testOnlyTargetDesktopChangesAndRoundTripPreservesWholeStore() throws {
        let original = try StoreFixture.root()
        let data = try DirectWallpaperStore.encode(original)
        let patch = try DirectWallpaperStore.patch(data, changes: [StoreFixture.change(image)])
        let updated = try DirectWallpaperStore.decode(patch.data)
        XCTAssertEqual(patch.undo.count, 1)
        for name in ["AllSpacesAndDisplays", "SystemDefault", "Displays", "FutureTopLevelField"] {
            XCTAssertTrue(NSDictionary(dictionary: [name: original[name]!]).isEqual(to: [name: updated[name]!]))
        }
        XCTAssertTrue(NSDictionary(dictionary: StoreFixture.target(original, space: StoreFixture.firstSpace))
            .isEqual(to: StoreFixture.target(updated, space: StoreFixture.firstSpace)))
        XCTAssertTrue(NSDictionary(dictionary: StoreFixture.target(original, display: StoreFixture.secondDisplay))
            .isEqual(to: StoreFixture.target(updated, display: StoreFixture.secondDisplay)))
        let target = StoreFixture.target(updated)
        XCTAssertEqual(target["UnrelatedEntryField"] as? String, "b-a")
        XCTAssertEqual((target["Idle"] as? [String: String])?["ScreenSaver"], "b-a")
        let desktop = target["Desktop"] as! [String: Any]
        XCTAssertEqual(desktop["CustomMetadata"] as? String, "keep")
        let content = desktop["Content"] as! [String: Any]
        XCTAssertEqual(content["UnknownContentField"] as? String, "keep")
        let configuration = try DirectWallpaperStore.decode((content["Choices"] as! [[String: Any]])[0]["Configuration"] as! Data)
        XCTAssertEqual((configuration["url"] as! [String: String])["relative"], image.absoluteString)
        let options = try DirectWallpaperStore.decode(content["EncodedOptionValues"] as! Data)["values"] as! [String: Any]
        XCTAssertEqual(((options["placement"] as! [String: Any])["picker"] as! [String: Any])["_0"] as? [String: String], ["id": "Crop"])
        XCTAssertEqual(options["color"] as? [String: String], ["existing": "preserve"])
        XCTAssertTrue(DirectWallpaperStore.containsChanges(patch.data, undo: patch.undo))
        let restored = try DirectWallpaperStore.decode(DirectWallpaperStore.restoring(patch.data, undo: patch.undo))
        XCTAssertTrue(NSDictionary(dictionary: original).isEqual(to: restored))
    }

    func testBatchedDisplayChangesAndIdenticalSelectionAvoidAnotherWrite() throws {
        let changes = [StoreFixture.change(image), StoreFixture.change(image, display: StoreFixture.secondDisplay, layout: .fit)]
        let first = try DirectWallpaperStore.patch(DirectWallpaperStore.encode(StoreFixture.root()), changes: changes)
        XCTAssertEqual(first.undo.count, 2)
        let repeated = try DirectWallpaperStore.patch(first.data, changes: changes, now: Date().addingTimeInterval(60))
        XCTAssertTrue(repeated.undo.isEmpty)
        XCTAssertEqual(first.data, repeated.data)
    }

    func testFitColorUsesSRGBAndColorOnlyChangeIsWrittenAndReversible() throws {
        let root = try StoreFixture.root()
        let original = try DirectWallpaperStore.encode(root)
        let color = WallpaperColor(red: 0.15, green: 0.35, blue: 0.65)
        let change = DirectWallpaperChange(spaceUUID: StoreFixture.secondSpace, displayUUID: StoreFixture.firstDisplay,
                                          imageURL: image, layout: .fit, backgroundColor: color)
        let patch = try DirectWallpaperStore.patch(original, changes: [change])
        let updated = try DirectWallpaperStore.decode(patch.data)
        let desktop = StoreFixture.target(updated)["Desktop"] as! [String: Any]
        let content = desktop["Content"] as! [String: Any]
        let values = try DirectWallpaperStore.decode(content["EncodedOptionValues"] as! Data)["values"] as! [String: Any]
        let outer = values["color"] as! [String: Any]
        let colorValue = (((outer["color"] as! [String: Any])["_0"] as! [String: Any])["color"] as! [String: Any])
        XCTAssertEqual(colorValue["components"] as? [Double], [0.15, 0.35, 0.65, 1.0])
        let colorSpace = try PropertyListSerialization.propertyList(from: colorValue["colorSpace"] as! Data, options: [], format: nil)
        XCTAssertEqual(colorSpace as? String, CGColorSpace.sRGB as String)
        XCTAssertEqual(try DirectWallpaperStore.patch(patch.data, changes: [change]).undo.count, 0)
        let otherColor = DirectWallpaperChange(spaceUUID: change.spaceUUID, displayUUID: change.displayUUID,
                                              imageURL: image, layout: .fit, backgroundColor: .black)
        let recolored = try DirectWallpaperStore.patch(patch.data, changes: [otherColor])
        XCTAssertEqual(recolored.undo.count, 1)
        XCTAssertFalse(DirectWallpaperStore.containsChanges(recolored.data, undo: patch.undo))
        let restored = try DirectWallpaperStore.decode(DirectWallpaperStore.restoring(recolored.data, undo: recolored.undo))
        XCTAssertTrue(NSDictionary(dictionary: updated).isEqual(to: restored))
        XCTAssertTrue(NSDictionary(dictionary: root).isEqual(to: try DirectWallpaperStore.decode(DirectWallpaperStore.restoring(patch.data, undo: patch.undo))))
    }

    func testNewDisplayOverrideCanBeRemovedWithoutChangingDefault() throws {
        let display = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        let data = try DirectWallpaperStore.encode(StoreFixture.root())
        let patch = try DirectWallpaperStore.patch(data, changes: [StoreFixture.change(image, display: display)])
        XCTAssertEqual(patch.undo.count, 1)
        let reversal = try DirectWallpaperStore.restoration(patch.data, undo: patch.undo)
        XCTAssertTrue(DirectWallpaperStore.containsChanges(reversal.data, undo: reversal.undo))
        XCTAssertTrue(NSDictionary(dictionary: try DirectWallpaperStore.decode(data))
            .isEqual(to: try DirectWallpaperStore.decode(reversal.data)))
    }

    func testRestorePreservesLaterScreensaverAndUnrelatedSpaceEdits() throws {
        let original = try StoreFixture.root()
        let patch = try DirectWallpaperStore.patch(DirectWallpaperStore.encode(original), changes: [StoreFixture.change(image)])
        var externallyEdited = try DirectWallpaperStore.decode(patch.data)
        StoreFixture.replace(&externallyEdited) { $0["Idle"] = ["ScreenSaver": "changed-later"] }
        StoreFixture.replace(&externallyEdited, space: StoreFixture.firstSpace) { $0["CustomField"] = "changed-later" }
        let restored = try DirectWallpaperStore.decode(DirectWallpaperStore.restoring(DirectWallpaperStore.encode(externallyEdited), undo: patch.undo))
        XCTAssertEqual((StoreFixture.target(restored)["Idle"] as! [String: String])["ScreenSaver"], "changed-later")
        XCTAssertEqual(StoreFixture.target(restored, space: StoreFixture.firstSpace)["CustomField"] as? String, "changed-later")
        XCTAssertTrue(NSDictionary(dictionary: StoreFixture.target(restored)["Desktop"] as! [String: Any])
            .isEqual(to: StoreFixture.target(original)["Desktop"] as! [String: Any]))
    }

    func testExternalTargetChangeBlocksRestoreAndTimestampChangesDoNot() throws {
        let patch = try DirectWallpaperStore.patch(DirectWallpaperStore.encode(StoreFixture.root()), changes: [StoreFixture.change(image)])
        var changed = try DirectWallpaperStore.decode(patch.data)
        StoreFixture.replace(&changed) { entry in
            var desktop = entry["Desktop"] as! [String: Any]
            desktop["LastUse"] = Date().addingTimeInterval(1_000)
            entry["Desktop"] = desktop
        }
        XCTAssertNoThrow(try DirectWallpaperStore.restoring(DirectWallpaperStore.encode(changed), undo: patch.undo))
        StoreFixture.replace(&changed) { $0["Desktop"] = ["External": "new picture"] }
        XCTAssertThrowsError(try DirectWallpaperStore.restoring(DirectWallpaperStore.encode(changed), undo: patch.undo))
        XCTAssertFalse(DirectWallpaperStore.containsChanges(try DirectWallpaperStore.encode(changed), undo: patch.undo))
    }

    func testCreatedOverrideWithLaterScreensaverChangeIsNotDeleted() throws {
        let display = "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"
        let patch = try DirectWallpaperStore.patch(DirectWallpaperStore.encode(StoreFixture.root()), changes: [StoreFixture.change(image, display: display)])
        var changed = try DirectWallpaperStore.decode(patch.data)
        StoreFixture.replace(&changed, display: display) { $0["Idle"] = ["ScreenSaver": "later"] }
        XCTAssertThrowsError(try DirectWallpaperStore.restoring(DirectWallpaperStore.encode(changed), undo: patch.undo))
    }

    func testUnknownGlobalLinkedAndMalformedFormatsAreRejected() throws {
        XCTAssertThrowsError(try DirectWallpaperStore.patch(Data("broken".utf8), changes: [StoreFixture.change(image)]))
        var root = try StoreFixture.root()
        root["AllSpacesAndDisplays"] = try StoreFixture.entry("global")
        XCTAssertThrowsError(try DirectWallpaperStore.patch(DirectWallpaperStore.encode(root), changes: [StoreFixture.change(image)]))
        root = try StoreFixture.root()
        StoreFixture.replace(&root) { $0["Type"] = "linked" }
        XCTAssertThrowsError(try DirectWallpaperStore.patch(DirectWallpaperStore.encode(root), changes: [StoreFixture.change(image)]))
        root = try StoreFixture.root()
        StoreFixture.replace(&root) { $0["Desktop"] = ["Content": ["Choices": [Any](), "EncodedOptionValues": Data([1, 2, 3])]] }
        XCTAssertThrowsError(try DirectWallpaperStore.patch(DirectWallpaperStore.encode(root), changes: [StoreFixture.change(image)]))
        let data = try DirectWallpaperStore.encode(StoreFixture.root())
        XCTAssertThrowsError(try DirectWallpaperStore.patch(data, changes: [StoreFixture.change(image), StoreFixture.change(image)]))
    }

    func testExistingConfigurationDefaultsToStandardMode() throws {
        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data("{\"schemaVersion\":1,\"paused\":false,\"rules\":{}}".utf8))
        XCTAssertFalse(configuration.directWallpaperMode)
        var updated = configuration
        updated.directWallpaperMode = true
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: JSONEncoder().encode(updated)), updated)
    }
}

private final class FakeWallpaperAgent: WallpaperAgentControlling {
    var events: [String] = []
    var onSuspend: (() throws -> Void)?
    var onReload: (() throws -> Void)?
    func suspend() throws { events.append("suspend"); try onSuspend?() }
    func reload() throws { events.append("reload"); try onReload?() }
    func resume() { events.append("resume") }
}

final class DirectWallpaperWriterTests: XCTestCase {
    private var directory: URL!
    private var store: URL!
    private var image: URL!
    private var backups: URL!
    private var agent: FakeWallpaperAgent!
    private var writer: DirectWallpaperWriter!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("DirectWallpaperTests-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = directory.appendingPathComponent("Index.plist")
        image = directory.appendingPathComponent("test.png")
        backups = directory.appendingPathComponent("Backups", isDirectory: true)
        try DirectWallpaperStore.encode(StoreFixture.root()).write(to: store)
        let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 8,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let destination = CGImageDestinationCreateWithURL(image as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        agent = FakeWallpaperAgent()
        writer = DirectWallpaperWriter(storeURL: store, backupsDirectory: backups, agent: agent)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }

    func testTransactionBacksUpOriginalAndRestoresIt() throws {
        let original = try Data(contentsOf: store)
        let receipt = try XCTUnwrap(writer.apply([StoreFixture.change(image)]))
        XCTAssertEqual(try Data(contentsOf: receipt.directory.appendingPathComponent("before.plist")), original)
        XCTAssertEqual(agent.events, ["suspend", "reload", "resume"])
        XCTAssertEqual(writer.latestBackup(), receipt)
        let permissions = try FileManager.default.attributesOfItem(atPath: receipt.directory.appendingPathComponent("before.plist").path)[.posixPermissions] as! Int
        XCTAssertEqual(permissions & 0o077, 0)
        let restored = try writer.restoreLatest()
        XCTAssertTrue(restored.restored)
        XCTAssertTrue(NSDictionary(dictionary: try DirectWallpaperStore.decode(Data(contentsOf: store)))
            .isEqual(to: try DirectWallpaperStore.decode(original)))
        XCTAssertThrowsError(try writer.restoreLatest())
    }

    func testRepeatedSelectionDoesNotRestartAgentOrReplaceBackup() throws {
        let receipt = try writer.apply([StoreFixture.change(image)])
        let events = agent.events
        XCTAssertNil(try writer.apply([StoreFixture.change(image)]))
        XCTAssertEqual(agent.events, events)
        XCTAssertEqual(writer.latestBackup(), receipt)
    }

    func testPreviewIsReadOnlyAndDoesNotCreateBackups() throws {
        let original = try Data(contentsOf: store)
        XCTAssertEqual(try writer.preview([StoreFixture.change(image)]).undo.count, 1)
        XCTAssertEqual(try Data(contentsOf: store), original)
        XCTAssertTrue(agent.events.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
    }

    func testAgentRestartFailureRollsBackAndAlwaysResumes() throws {
        let original = try Data(contentsOf: store)
        var calls = 0
        agent.onReload = { calls += 1; if calls == 1 { throw DirectWallpaperError.reloadFailed } }
        XCTAssertThrowsError(try writer.apply([StoreFixture.change(image)]))
        XCTAssertEqual(try Data(contentsOf: store), original)
        XCTAssertEqual(agent.events.last, "resume")
        XCTAssertTrue(try XCTUnwrap(writer.latestBackup()).restored)
    }

    func testConcurrentUnrelatedChangeBeforeSuspensionIsPreserved() throws {
        agent.onSuspend = { [self] in
            var root = try DirectWallpaperStore.decode(Data(contentsOf: store))
            root["ExternalField"] = "created-before-write"
            try DirectWallpaperStore.encode(root).write(to: store)
        }
        _ = try writer.apply([StoreFixture.change(image)])
        let root = try DirectWallpaperStore.decode(Data(contentsOf: store))
        XCTAssertEqual(root["ExternalField"] as? String, "created-before-write")
    }

    func testConflictingRestoreLeavesExternalPictureUntouchedAndDoesNotStopAgent() throws {
        _ = try writer.apply([StoreFixture.change(image)])
        var changed = try DirectWallpaperStore.decode(Data(contentsOf: store))
        StoreFixture.replace(&changed) { $0["Desktop"] = ["External": "picture"] }
        let externalData = try DirectWallpaperStore.encode(changed)
        try externalData.write(to: store)
        let events = agent.events
        XCTAssertThrowsError(try writer.restoreLatest())
        XCTAssertEqual(try Data(contentsOf: store), externalData)
        XCTAssertEqual(agent.events, events)
    }

    func testUnsupportedStoreAndMissingImageNeverSignalAgent() throws {
        try Data("not a plist".utf8).write(to: store)
        XCTAssertThrowsError(try writer.apply([StoreFixture.change(image)]))
        XCTAssertTrue(agent.events.isEmpty)
        try DirectWallpaperStore.encode(StoreFixture.root()).write(to: store)
        XCTAssertThrowsError(try writer.apply([StoreFixture.change(directory.appendingPathComponent("missing.png"))]))
        try Data("no longer an image".utf8).write(to: image)
        XCTAssertThrowsError(try writer.apply([StoreFixture.change(image)]))
        XCTAssertTrue(agent.events.isEmpty)
    }

    func testStorePermissionsAreRetained() throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: store.path)
        _ = try writer.apply([StoreFixture.change(image)])
        let permissions = try FileManager.default.attributesOfItem(atPath: store.path)[.posixPermissions] as! Int
        XCTAssertEqual(permissions, 0o600)
    }

    func testAgentOverwritingChangeIsDetectedAndOriginalRetained() throws {
        let original = try Data(contentsOf: store)
        agent.onReload = { [self] in try original.write(to: store) }
        XCTAssertThrowsError(try writer.apply([StoreFixture.change(image)]))
        XCTAssertEqual(try Data(contentsOf: store), original)
        XCTAssertTrue(try XCTUnwrap(writer.latestBackup()).restored)
    }

    func testConcurrentTargetChangeDuringReloadIsNeverOverwrittenByRecovery() throws {
        agent.onReload = { [self] in
            var root = try DirectWallpaperStore.decode(Data(contentsOf: store))
            StoreFixture.replace(&root) { $0["Desktop"] = ["External": "changed-during-reload"] }
            try DirectWallpaperStore.encode(root).write(to: store)
        }
        XCTAssertThrowsError(try writer.apply([StoreFixture.change(image)]))
        let root = try DirectWallpaperStore.decode(Data(contentsOf: store))
        XCTAssertEqual((StoreFixture.target(root)["Desktop"] as! [String: String])["External"], "changed-during-reload")
        XCTAssertFalse(try XCTUnwrap(writer.latestBackup()).restored)
        XCTAssertEqual(agent.events.last, "resume")
    }

    func testFailedRestoreRetainsBackupForAnotherAttempt() throws {
        _ = try writer.apply([StoreFixture.change(image)])
        let applied = try Data(contentsOf: store)
        var calls = 0
        agent.onReload = { calls += 1; if calls == 1 { throw DirectWallpaperError.reloadFailed } }
        XCTAssertThrowsError(try writer.restoreLatest())
        XCTAssertEqual(try Data(contentsOf: store), applied)
        XCTAssertFalse(try XCTUnwrap(writer.latestBackup()).restored)
        agent.onReload = nil
        XCTAssertTrue(try writer.restoreLatest().restored)
    }

    func testBackupsStayBoundedAndLatestIsKept() throws {
        for index in 0..<12 {
            _ = try writer.apply([StoreFixture.change(image, layout: index.isMultiple(of: 2) ? .fill : .fit)])
        }
        let snapshots = try FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil)
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("before.plist").path) }
        XCTAssertEqual(snapshots.count, 10)
        let latest = try XCTUnwrap(writer.latestBackup()).directory
        XCTAssertTrue(snapshots.contains { $0.lastPathComponent == latest.lastPathComponent })
        XCTAssertTrue(FileManager.default.fileExists(atPath: latest.appendingPathComponent("before.plist").path))
    }

    func testPreparationFailureStillResumesAgent() throws {
        let original = try Data(contentsOf: store)
        agent.onSuspend = { [self] in
            try FileManager.default.removeItem(at: backups)
            try Data([1]).write(to: backups)
        }
        XCTAssertThrowsError(try writer.apply([StoreFixture.change(image)]))
        XCTAssertEqual(try Data(contentsOf: store), original)
        XCTAssertEqual(agent.events.last, "resume")
    }
}
