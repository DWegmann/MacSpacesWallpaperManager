import SwiftUI
import WallpaperCore

@MainActor
struct MacSpacesWallpaperManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Mac Spaces Wallpaper Manager", id: "main") {
            ContentView()
                .environmentObject(model)
                .onAppear { delegate.model = model; model.start() }
        }
        .defaultSize(width: 1120, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Hintergrundbilder") {
                Button("Nächstes Bild für sichtbare Spaces") { model.nextVisibleImages() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button(model.isPaused ? "Automatik fortsetzen" : "Automatik pausieren") { model.togglePaused() }
                Divider()
                Button("Spaces aktualisieren") { model.refreshSpaces() }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        MenuBarExtra("Mac Spaces Wallpaper Manager", systemImage: "rectangle.on.rectangle.angled") {
            MenuBarView().environmentObject(model)
        }

        Settings {
            SettingsView().environmentObject(model)
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
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Mac Spaces Wallpaper Manager · \(model.isPaused ? "pausiert" : "aktiv")")
        if model.directModeEnabled { Text("Direktmodus für alle Desktop-Spaces") }
        Divider()
        Button("Mac Spaces Wallpaper Manager öffnen") {
            openWindow(id: "main")
            showMainWindow()
        }
        Button("Nächstes Hintergrundbild") { model.nextVisibleImages() }
            .disabled(model.isPaused || model.configuredCount == 0)
        Button(model.isPaused ? "Automatik fortsetzen" : "Automatik pausieren") { model.togglePaused() }
        Divider()
        ForEach(model.spaces.filter(\.isVisible)) { space in
            Text("\(space.title) · \(space.display.name)")
        }
        Divider()
        Button("Beenden") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var showRestoreConfirmation = false

    var body: some View {
        Form {
            Section("Allgemein") {
                Toggle("Bei der Anmeldung öffnen", isOn: Binding(
                    get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }
                ))
                if model.loginNeedsApproval {
                    Text("Bitte bestätige Mac Spaces Wallpaper Manager unter Systemeinstellungen → Allgemein → Anmeldeobjekte.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Nach dem Schließen des Fensters läuft die App in der Menüleiste weiter.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Spaces") {
                Text("Jeder Desktop erhält seinen eigenen Bilderordner. Im Standardmodus wird ein inaktiver Desktop beim nächsten Besuch aktualisiert. Vollbild-Spaces werden ausgelassen.")
                Text("Die Space-Erkennung verwendet eine nicht öffentliche macOS-Schnittstelle. Nach einem macOS-Update kann eine Anpassung nötig sein.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Direktmodus (experimentell)") {
                Toggle("Auch inaktive Spaces sofort aktualisieren", isOn: Binding(
                    get: { model.directModeEnabled }, set: { model.setDirectMode($0) }
                ))
                .disabled(!model.directModeAvailable || !model.isWritable || model.isApplyingDirect)
                Text("Verwendet einen inoffiziellen macOS-Speicherzugriff. Vor jeder Änderung wird eine Sicherung erstellt und der Hintergrunddienst neu gestartet. Nach macOS-Updates kann eine Anpassung nötig sein.")
                    .font(.caption).foregroundStyle(.secondary)
                Label("Beim Bildwechsel kann der Hintergrund kurz flackern.", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
                if !model.directModeAvailable {
                    Text("Benötigt macOS 14 oder neuer und eine lesbare Hintergrund-Konfiguration.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if model.isApplyingDirect {
                    HStack { ProgressView().controlSize(.small); Text("Hintergründe werden aktualisiert …").font(.caption) }
                }
                if let backup = model.lastDirectBackup {
                    Text("Letzte Sicherung: \(backup.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(backup.changeCount) Zuordnung(en)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Letzte Direktmodus-Änderung rückgängig machen …") { showRestoreConfirmation = true }
                        .disabled(!model.canRestoreDirectBackup || !model.isWritable)
                    Button("Sicherungen im Finder zeigen") { model.showDirectBackups() }
                }
                if let notice = model.directModeNotice { Text(notice).font(.caption).foregroundStyle(.secondary) }
            }
            Section("Daten") {
                Text("Bilder bleiben in deinem Ordner. Zuordnungen werden lokal auf diesem Mac gespeichert.")
                Button("Einstellungsdatei im Finder zeigen") { model.showConfigurationFile() }
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 660)
        .onAppear { model.updateLoginStatus(); model.refreshDirectBackup() }
        .confirmationDialog("Letzte Direktmodus-Änderung zurücknehmen?", isPresented: $showRestoreConfirmation, titleVisibility: .visible) {
            Button("Gesicherte Hintergründe wiederherstellen") { model.restoreDirectBackup() }
        } message: {
            Text("Nur die zuletzt von der App geänderten Hintergründe werden zurückgesetzt. Die Automatik wird dabei pausiert. Wurde ein betroffener Hintergrund inzwischen außerhalb der App geändert, wird die Wiederherstellung abgebrochen.")
        }
    }
}
