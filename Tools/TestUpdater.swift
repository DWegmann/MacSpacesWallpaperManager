// Compiled by test-updates.py into an isolated app bundle; never launches the wallpaper app.
import AppKit
import CryptoKit
import Sparkle

@MainActor
final class FeedProbe: NSObject, SPUUpdaterDelegate {
    let url: String
    var completed = false
    var foundVersion: String?
    var failure: NSError?

    init(url: String) { self.url = url }

    func feedURLString(for updater: SPUUpdater) -> String? { url }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundVersion = item.versionString
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        failure = error as NSError?
        completed = true
    }
}

@main
struct TestUpdater {
    @MainActor
    static func main() throws {
        let arguments = CommandLine.arguments
        func require(_ condition: Bool, _ message: String) {
            guard condition else { fputs("FAIL: \(message)\n", stderr); exit(1) }
        }
        let mode = arguments[1]
        if mode == "key" {
            let key = Curve25519.Signing.PrivateKey()
            let url = URL(fileURLWithPath: arguments[2])
            FileManager.default.createFile(atPath: url.path, contents: key.rawRepresentation.base64EncodedData(),
                                           attributes: [.posixPermissions: 0o600])
            print(key.publicKey.rawRepresentation.base64EncodedString())
            return
        }

        let bundle = Bundle.main
        require(bundle.bundleIdentifier?.hasPrefix("app.spacepaper.mac.updater-tests.") == true,
                "Tests must use their own bundle identifier")
        if mode == "cleanup" {
            UserDefaults.standard.removePersistentDomain(forName: bundle.bundleIdentifier!)
            return
        }
        _ = NSApplication.shared
        if mode == "preferences" || mode == "persisted-preferences" {
            let updates = UpdateController()
            require(updates.startupError == nil, updates.startupError ?? "")
            require(updates.canCheckForUpdates, "Manual checks must remain available")
            if mode == "preferences" {
                require(updates.automaticallyChecksForUpdates, "Automatic checks must default to on")
                updates.setAutomaticallyChecksForUpdates(false)
                require(!updates.automaticallyChecksForUpdates, "Disabling automatic checks must update the UI")
                UserDefaults.standard.synchronize()
            } else {
                require(!updates.automaticallyChecksForUpdates, "Disabled automatic checks must survive a restart")
            }
            print("PASS: \(mode)")
            return
        }

        // Only probe metadata. No archive is downloaded, installed, or relaunched.
        let probe = FeedProbe(url: arguments[2])
        let updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle,
                                 userDriver: SPUStandardUserDriver(hostBundle: bundle, delegate: nil), delegate: probe)
        require(!updater.automaticallyDownloadsUpdates && !updater.allowsAutomaticUpdates,
                "Automatic downloads/installations must stay disabled")
        require(!updater.sendsSystemProfile, "System profiling must stay disabled")
        try updater.start()
        updater.checkForUpdateInformation()
        let deadline = Date().addingTimeInterval(15)
        while !probe.completed && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        require(probe.completed, "Update probe timed out")
        if mode == "valid-feed" {
            require(probe.failure == nil, "Valid feed rejected: \(String(describing: probe.failure))")
            require(probe.foundVersion == "6", "New version was not detected")
        } else {
            require(probe.foundVersion == nil && probe.failure != nil,
                    "Tampered feed must be rejected before offering an update")
        }
        print("PASS: \(mode)")
    }
}
