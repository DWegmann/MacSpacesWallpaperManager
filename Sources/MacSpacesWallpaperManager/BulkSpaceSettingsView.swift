import SwiftUI
import WallpaperCore

private struct BulkSettingsDraft: Equatable {
    var changeFolder = false
    var folderURL: URL?
    var changeRecursive = false
    var recursive = true
    var changeRotation = false
    var rotation: RotationMode = .manual
    var changeLayout = false
    var layout: ImageLayout = .fill
    var changeColor = false
    var color: Color = .black
    var changeShuffle = false
    var shuffle = true
    var changeEnabled = false
    var enabled = true

    var changes: SpaceRuleChanges {
        var changes = SpaceRuleChanges()
        if changeRecursive { changes.recursive = recursive }
        if changeRotation { changes.rotation = rotation }
        if changeLayout { changes.layout = layout }
        if changeColor { changes.backgroundColor = WallpaperColor(color) }
        if changeShuffle { changes.shuffle = shuffle }
        if changeEnabled { changes.enabled = enabled }
        return changes
    }

    var canApply: Bool {
        (!changes.isEmpty || changeFolder) && (!changeFolder || folderURL != nil)
    }
}

struct BulkSpaceSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var draft = BulkSettingsDraft()
    @ViewState private var resultMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mehrere Spaces gemeinsam einrichten")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text("\(model.selectedSpaces.count) \(model.selectedSpaces.count == 1 ? "Space ausgewählt" : "Spaces ausgewählt")")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Wähle links die Spaces aus. Nur angehakte Einstellungen werden übernommen.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                selectionCard
                folderCard
                behaviorCard
                applyCard
            }
            .padding(.horizontal, 34).padding(.top, 30).padding(.bottom, 24)
            .frame(maxWidth: 1080).frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: model.selectedSpaceIDs) { _ in resultMessage = nil }
        .onChange(of: draft) { _ in resultMessage = nil }
    }

    private var selectionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Ausgewählte Spaces", systemImage: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Alle auswählen") { model.selectAllSpaces() }.buttonStyle(.link)
                Button("Auswahl leeren") { model.clearSpaceSelection() }.buttonStyle(.link)
            }
            .font(.system(size: 11))
            if model.selectedSpaces.isEmpty {
                Text("Noch keine Spaces ausgewählt.").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.selectedSpaces) { space in
                            Label("\(space.title) · \(space.display.name)", systemImage: "desktopcomputer")
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: min(120, CGFloat(model.selectedSpaces.count) * 22))
            }
        }
        .padding(18).bulkCard()
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            field("Bilderordner ändern", selected: $draft.changeFolder) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").foregroundStyle(Color.paperAccent)
                    Text(draft.folderURL?.path ?? "Kein gemeinsamer Ordner ausgewählt")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 5)
                    Button(draft.folderURL == nil ? "Ordner auswählen …" : "Ändern …") {
                        model.chooseBulkFolder { draft.folderURL = $0; resultMessage = nil }
                    }
                    .controlSize(.small)
                }
            }
            Divider()
            field("Unterordner-Einstellung ändern", selected: $draft.changeRecursive) {
                Toggle("Unterordner einbeziehen", isOn: $draft.recursive).toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
        }
        .padding(18).bulkCard().disabled(!model.isWritable || model.isApplyingDirect)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            field("Bildwechsel ändern", selected: $draft.changeRotation) {
                Picker("Bild wechseln", selection: $draft.rotation) {
                    ForEach(RotationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 350)
            }
            Divider()
            field("Darstellung ändern", selected: $draft.changeLayout) {
                Picker("Darstellung", selection: $draft.layout) {
                    ForEach(ImageLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 350)
            }
            Divider()
            field("Hintergrundfarbe ändern", selected: $draft.changeColor) {
                ColorPicker("Farbe: \(WallpaperColor(draft.color).displayName)", selection: $draft.color, supportsOpacity: false)
                    .frame(maxWidth: 350)
                Text("Wird bei „An Bildschirm anpassen“ für die freien Flächen verwendet.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
            field("Reihenfolge ändern", selected: $draft.changeShuffle) {
                Toggle("Zufällige Reihenfolge", isOn: $draft.shuffle).toggleStyle(.checkbox)
            }
            Divider()
            field("Aktivierung ändern", selected: $draft.changeEnabled) {
                Toggle("Hintergründe für diese Spaces aktivieren", isOn: $draft.enabled).toggleStyle(.checkbox)
            }
        }
        .font(.system(size: 12))
        .padding(18).bulkCard().disabled(!model.isWritable || model.isApplyingDirect)
    }

    private var applyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(Color.paperAccent)
            }
            HStack {
                Button {
                    let count = model.applyBulkChanges(draft.changes, folderURL: draft.changeFolder ? draft.folderURL : nil)
                    if count > 0 { resultMessage = "Einstellungen für \(count) \(count == 1 ? "Space" : "Spaces") gespeichert." }
                } label: {
                    Text("Auf \(model.selectedSpaces.count) \(model.selectedSpaces.count == 1 ? "Space" : "Spaces") anwenden")
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!draft.canApply || model.selectedSpaces.isEmpty || !model.isWritable || model.isApplyingDirect)
                Spacer()
                Button("Mehrfachauswahl beenden") { model.toggleMultipleSelection() }.buttonStyle(.link)
                    .font(.system(size: 11))
            }
            Text(model.directModeEnabled
                 ? "Der Direktmodus berücksichtigt auch inaktive Desktop-Spaces. Beim Bildwechsel kann der Hintergrund kurz flackern."
                 : "Im Standardmodus werden inaktive Spaces beim nächsten Besuch aktualisiert.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .padding(18).bulkCard()
    }

    private func field<Content: View>(_ title: String, selected: Binding<Bool>, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(title, isOn: selected).toggleStyle(.checkbox).font(.system(size: 12, weight: .medium))
            VStack(alignment: .leading, spacing: 8, content: content)
                .padding(.leading, 20).disabled(!selected.wrappedValue)
        }
    }
}

private extension View {
    func bulkCard() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
    }
}
