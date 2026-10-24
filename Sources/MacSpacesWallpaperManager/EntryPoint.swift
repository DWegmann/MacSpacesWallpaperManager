import AppKit
import Foundation
import WallpaperCore

@main
struct EntryPoint {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--direct-store-check") {
            _ = NSApplication.shared
            do {
                let spaces = try SpaceCatalog().read()
                guard let target = spaces.first(where: { !$0.isVisible }) ?? spaces.first else { throw SpaceCatalogError.invalidData }
                let writer = DirectWallpaperWriter()
                let before = try Data(contentsOf: writer.storeURL)
                let patch = try writer.preview([DirectWallpaperChange(
                    spaceUUID: target.uuid, displayUUID: target.display.id,
                    imageURL: URL(fileURLWithPath: "/private/tmp/MacSpacesWallpaperManager-readonly-check.png"), layout: .fill
                )])
                let restored = try DirectWallpaperStore.restoring(patch.data, undo: patch.undo)
                guard let originalRoot = try PropertyListSerialization.propertyList(from: before, options: [], format: nil) as? NSDictionary,
                      let restoredRoot = try PropertyListSerialization.propertyList(from: restored, options: [], format: nil) as? NSDictionary,
                      originalRoot.isEqual(restoredRoot), try Data(contentsOf: writer.storeURL) == before else {
                    throw DirectWallpaperError.concurrentChange
                }
                print("Direktmodus-Prüfung erfolgreich: \(patch.undo.count) gezielte Zuordnung(en), Rücknahme geprüft. Keine Dateien geschrieben und kein Hintergrunddienst neu gestartet.")
            } catch {
                fputs("Direktmodus-Prüfung fehlgeschlagen: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        } else if CommandLine.arguments.contains("--diagnostics") {
            // Read-only integration check: does not load rules, scan user folders or change wallpapers.
            _ = NSApplication.shared
            do {
                let spaces = try SpaceCatalog().read()
                let report: [[String: Any]] = spaces.map {
                    ["id": $0.id, "title": $0.title, "display": $0.display.name, "visible": $0.isVisible]
                }
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                print(String(decoding: data, as: UTF8.self))
            } catch {
                fputs("Space-Erkennung fehlgeschlagen: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
        } else {
            MacSpacesWallpaperManagerApp.main()
        }
    }
}
