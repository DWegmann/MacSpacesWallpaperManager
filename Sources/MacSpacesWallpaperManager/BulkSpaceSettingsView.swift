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
                    Text("Set up multiple Spaces together")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    Text("\(model.selectedSpaces.count) \(model.selectedSpaces.count == 1 ? "Space selected" : "Spaces selected")")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                    Text("Select Spaces on the left. Only checked settings will be applied.")
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
                Label("Selected Spaces", systemImage: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Select all") { model.selectAllSpaces() }.buttonStyle(.link)
                Button("Clear selection") { model.clearSpaceSelection() }.buttonStyle(.link)
            }
            .font(.system(size: 11))
            if model.selectedSpaces.isEmpty {
                Text("No Spaces selected yet.").font(.system(size: 12)).foregroundStyle(.secondary)
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
            field("Change image folder", selected: $draft.changeFolder) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill").foregroundStyle(Color.paperAccent)
                    Text(draft.folderURL?.path ?? "No shared folder selected")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 5)
                    Button(draft.folderURL == nil ? "Choose folder…" : "Change…") {
                        model.chooseBulkFolder { draft.folderURL = $0; resultMessage = nil }
                    }
                    .controlSize(.small)
                }
            }
            Divider()
            field("Change subfolder setting", selected: $draft.changeRecursive) {
                Toggle("Include subfolders", isOn: $draft.recursive).toggleStyle(.checkbox)
                    .font(.system(size: 12))
            }
        }
        .padding(18).bulkCard().disabled(!model.isWritable || model.isApplyingDirect)
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            field("Change rotation", selected: $draft.changeRotation) {
                Picker("Change image", selection: $draft.rotation) {
                    ForEach(RotationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 350)
            }
            Divider()
            field("Change image scaling", selected: $draft.changeLayout) {
                Picker("Image scaling", selection: $draft.layout) {
                    ForEach(ImageLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .frame(maxWidth: 350)
            }
            Divider()
            field("Change background color", selected: $draft.changeColor) {
                ColorPicker("Color: \(WallpaperColor(draft.color).displayName)", selection: $draft.color, supportsOpacity: false)
                    .frame(maxWidth: 350)
                Text("Used for unused areas when “Fit to screen” is selected.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Divider()
            field("Change order", selected: $draft.changeShuffle) {
                Toggle("Random order", isOn: $draft.shuffle).toggleStyle(.checkbox)
            }
            Divider()
            field("Change enabled status", selected: $draft.changeEnabled) {
                Toggle("Enable wallpapers for these Spaces", isOn: $draft.enabled).toggleStyle(.checkbox)
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
                    if count > 0 { resultMessage = "Settings saved for \(count) \(count == 1 ? "Space" : "Spaces")." }
                } label: {
                    Text("Apply to \(model.selectedSpaces.count) \(model.selectedSpaces.count == 1 ? "Space" : "Spaces")")
                        .padding(.horizontal, 10).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .disabled(!draft.canApply || model.selectedSpaces.isEmpty || !model.isWritable || model.isApplyingDirect)
                Spacer()
                Button("Exit multiple selection") { model.toggleMultipleSelection() }.buttonStyle(.link)
                    .font(.system(size: 11))
            }
            Text(model.directModeEnabled
                 ? "Direct mode also updates inactive desktop Spaces. The wallpaper may briefly flicker when changing images."
                 : "In standard mode, inactive Spaces are updated the next time you visit them.")
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
