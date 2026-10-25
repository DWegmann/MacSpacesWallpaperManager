import Combine
import Sparkle
import SwiftUI

@MainActor
final class UpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var startupError: String?

    private let controller: SPUStandardUpdaterController

    init() {
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

        // `swift run` produces a bare executable without the bundle metadata required by Sparkle.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            startupError = "Updates sind in der gebauten App verfügbar. Bitte starte die App aus dem Programme-Ordner."
            return
        }

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates)
            .assign(to: &$automaticallyChecksForUpdates)

        do {
            try controller.updater.start()
        } catch {
            startupError = "Die Update-Prüfung konnte nicht gestartet werden: \(error.localizedDescription)"
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates, startupError == nil else { return }
        controller.checkForUpdates(nil)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard startupError == nil else { return }
        // Sparkle persists this preference. Do not reset it when the app launches.
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updates: UpdateController

    var body: some View {
        Button("Nach Updates suchen …") { updates.checkForUpdates() }
            .disabled(!updates.canCheckForUpdates || updates.startupError != nil)
    }
}
