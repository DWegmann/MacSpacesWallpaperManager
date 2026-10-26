import SwiftUI
import WallpaperCore

@MainActor
struct MacSpacesWallpaperManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var updates = UpdateController()

    var body: some Scene {
        Window("Mac Spaces Wallpaper Manager", id: "main") {
            ContentView()
                .environmentObject(model)
                .onAppear { delegate.model = model; model.start() }
        }
        .defaultSize(width: 1120, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updates: updates)
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Wallpapers") {
                Button("Next image for visible Spaces") { model.nextVisibleImages() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button(model.isPaused ? "Resume automatic rotation" : "Pause automatic rotation") { model.togglePaused() }
                Divider()
                Button("Refresh Spaces") { model.refreshSpaces() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra("Mac Spaces Wallpaper Manager", systemImage: "rectangle.on.rectangle.angled") {
            MenuBarView(updates: updates).environmentObject(model)
        }

        Settings {
            SettingsView(updates: updates).environmentObject(model)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        for window in NSApp.windows where window.canBecomeMain {
            window.collectionBehavior.insert(.moveToActiveSpace)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) { model?.stop() }
}

@MainActor
func showMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" || $0.title == "Mac Spaces Wallpaper Manager" }) {
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct MenuBarView: View {
    @ObservedObject var updates: UpdateController
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Mac Spaces Wallpaper Manager · \(model.isPaused ? "paused" : "active")")
        if model.directModeEnabled { Text("Direct mode for all desktop Spaces") }
        Divider()
        Button("Open Mac Spaces Wallpaper Manager") {
            openWindow(id: "main")
            showMainWindow()
        }
        Button("Next wallpaper") { model.nextVisibleImages() }
            .disabled(model.isPaused || model.configuredCount == 0)
        Button(model.isPaused ? "Resume automatic rotation" : "Pause automatic rotation") { model.togglePaused() }
        Divider()
        ForEach(model.spaces.filter(\.isVisible)) { space in
            Text("\(space.title) · \(space.display.name)")
            Text("Current image: \(model.currentImageURL(for: space)?.lastPathComponent ?? "Not available")")
        }
        Divider()
        CheckForUpdatesButton(updates: updates)
        Button("Quit") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

private struct SettingsView: View {
    @ObservedObject var updates: UpdateController
    @EnvironmentObject private var model: AppModel
    @ViewState private var showRestoreConfirmation = false

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
                ))
                if model.loginNeedsApproval {
                    Text("Please approve Mac Spaces Wallpaper Manager in System Settings → General → Login Items.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("The app keeps running in the menu bar after you close the window.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { updates.automaticallyChecksForUpdates },
                    set: { updates.setAutomaticallyChecksForUpdates($0) }
                ))
                .disabled(updates.startupError != nil)
                CheckForUpdatesButton(updates: updates)
                Text("Checks GitHub daily for new versions. Click to start the download and installation; the app will then restart.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = updates.startupError {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Spaces") {
                Text("Each desktop has its own image folder. In standard mode, inactive desktops are updated the next time you visit them. Full-screen Spaces are skipped.")
                Text("Space detection uses a private macOS interface. It may need adjustment after a macOS update.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Direct mode (experimental)") {
                Toggle("Update inactive Spaces immediately", isOn: Binding(
                    get: { model.directModeEnabled }, set: { model.setDirectMode($0) }
                ))
                .disabled(!model.directModeAvailable || !model.isWritable || model.isApplyingDirect)
                Text("Uses an unofficial method to access the macOS wallpaper store. Creates a backup before each change and restarts the wallpaper service afterward. It may need adjustment after macOS updates.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("The wallpaper may briefly flicker when changing images.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.directModeAvailable {
                    Text("Requires macOS 14 or later and a readable wallpaper configuration.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.isApplyingDirect {
                    HStack { ProgressView().controlSize(.small); Text("Updating wallpapers…").font(.caption) }
                }
                if let backup = model.lastDirectBackup {
                    Text("Last backup: \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(backup.changeCount) \(backup.changeCount == 1 ? "assignment" : "assignments")")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Undo last direct-mode change…") { showRestoreConfirmation = true }
                        .disabled(!model.canRestoreDirectBackup || !model.isWritable)
                    Button("Show backups in Finder") { model.showDirectBackups() }
                }
                if let notice = model.directModeNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Data") {
                Text("Images stay in your folder. Assignments are saved locally on this Mac.")
                Button("Show configuration file in Finder") { model.showConfigurationFile() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 660)
        .onAppear { model.updateLoginStatus(); model.refreshDirectBackup() }
        .confirmationDialog("Undo the last direct-mode change?", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("Restore backed-up wallpapers") { model.restoreDirectBackup() }
        } message: {
            Text("Only the wallpapers last changed by the app will be restored. Automatic rotation will be paused. If an affected wallpaper has since changed outside the app, restoration will be canceled.")
        }
    }
}
