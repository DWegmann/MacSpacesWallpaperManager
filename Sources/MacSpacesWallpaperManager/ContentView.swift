import SwiftUI
import WallpaperCore

// Explicit type alias keeps the macOS 13 property wrapper when newer SDKs also export a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

extension Color {
    static let paperAccent = Color(red: 0.22, green: 0.47, blue: 0.38)
}

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 280)
        } detail: {
            if model.isSelectingMultipleSpaces {
                BulkSpaceSettingsView()
            } else if let space = model.selectedSpace {
                SpaceDetailView(space: space)
                    .id(space.id)
            } else {
                noSpaces
            }
        }
        .tint(.paperAccent)
        .frame(minWidth: 890, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .safeAreaInset(edge: .top, spacing: 0) {
            if let error = model.persistenceError {
                NoticeView(text: error, symbol: "exclamationmark.triangle.fill", warning: true)
                    .padding(.horizontal, 20).padding(.vertical, 8)
            }
            if let notice = model.directModeNotice {
                HStack(alignment: .top, spacing: 8) {
                    NoticeView(text: notice, symbol: "info.circle", warning: true)
                    Button { model.directModeNotice = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).accessibilityLabel("Dismiss notice").padding(.top, 10)
                }
                .padding(.horizontal, 20).padding(.vertical, 8)
            }
            if model.directModeEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.horizontal.circle")
                    Text(model.isApplyingDirect ? "Direct mode: Updating wallpapers…" : "Direct mode active · Inactive desktop Spaces are also updated.")
                    Spacer()
                }
                .font(.system(size: 11)).foregroundStyle(Color.paperAccent)
                .padding(10).background(Color.paperAccent.opacity(0.07))
            }
            if model.isPaused {
                HStack(spacing: 9) {
                    Image(systemName: "pause.circle.fill")
                    Text("Automatic rotation paused. Your assignments are saved.")
                    Spacer()
                    Button("Resume") { model.togglePaused() }.buttonStyle(.link)
                }
                .font(.system(size: 12))
                .padding(12)
                .background(Color.orange.opacity(0.12))
            }
        }
        .alert("Mac Spaces Wallpaper Manager", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK") { model.actionError = nil }
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var noSpaces: some View {
        VStack(spacing: 18) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Color.paperAccent)
            Text("Your desktops").font(.system(size: 26, weight: .semibold))
            Text(model.spaceError ?? "Detecting available Spaces…")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            Button("Refresh again") { model.refreshSpaces() }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    private var displays: [ScreenIdentity] {
        var seen = Set<String>()
        return model.spaces.map(\.display).filter { seen.insert($0.id).inserted }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color.paperAccent.gradient)
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 18, weight: .medium)).foregroundStyle(.white)
                }
                .frame(width: 37, height: 37)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mac Spaces\nWallpaper Manager")
                        .font(.system(size: 14, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Wallpapers for each Space").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18).padding(.top, 30).padding(.bottom, 30)

            HStack {
                Text("YOUR SPACES").font(.system(size: 10, weight: .semibold)).tracking(1.3).foregroundStyle(.secondary)
                Spacer()
                Button(model.isSelectingMultipleSpaces ? "Done" : "Select") { model.toggleMultipleSelection() }
                    .buttonStyle(.plain).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.paperAccent)
                    .help("Edit multiple Spaces together")
                Button { model.refreshSpaces() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Refresh Spaces (⌘R)")
                    .accessibilityLabel("Refresh Spaces")
            }
            .padding(.horizontal, 20).padding(.bottom, 10)
            if model.isSelectingMultipleSpaces {
                Text("\(model.selectedSpaceIDs.count) selected")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .padding(.horizontal, 20).padding(.bottom, 10)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(displays, id: \.id) { display in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(display.name, systemImage: "display").lineLimit(1)
                                Spacer(minLength: 4)
                                if model.isSelectingMultipleSpaces {
                                    Button("All") { model.selectAllSpaces(on: display.id) }
                                        .buttonStyle(.plain).foregroundStyle(Color.paperAccent)
                                        .accessibilityLabel("Select all Spaces on \(display.name)")
                                }
                            }
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .padding(.horizontal, 10).padding(.bottom, 4)
                            ForEach(model.spaces.filter { $0.display.id == display.id }) { space in
                                spaceRow(space)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
            }

            VStack(alignment: .leading, spacing: 13) {
                Divider()
                HStack(spacing: 7) {
                    Circle().fill(model.isPaused ? .orange : Color.paperAccent).frame(width: 6, height: 6)
                    Text(model.isPaused ? "Automatic rotation paused" : "\(model.configuredCount) \(model.configuredCount == 1 ? "Space" : "Spaces") configured")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text("Stays active in the menu bar.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                HStack {
                    settingsButton
                    Spacer()
                    if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
                        Text("v\(version)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(20)
        }
        .background(.ultraThinMaterial)
    }

    private func spaceRow(_ space: DesktopSpace) -> some View {
        let rule = model.rule(for: space.id)
        let selected = model.isSelectingMultipleSpaces ? model.selectedSpaceIDs.contains(space.id) : model.selectedSpaceID == space.id
        return Button { model.selectSpace(space.id) } label: {
            HStack(spacing: 11) {
                if model.isSelectingMultipleSpaces {
                    Image(systemName: selected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15)).foregroundStyle(selected ? Color.paperAccent : .secondary)
                }
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.paperAccent.opacity(selected ? 0.16 : 0.06))
                    Image(systemName: rule.folderPath == nil ? "desktopcomputer" : "photo.on.rectangle")
                        .font(.system(size: 17)).foregroundStyle(selected ? Color.paperAccent : .secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if space.isVisible {
                        Circle().fill(Color.paperAccent).frame(width: 7, height: 7).padding(4)
                    }
                }
                .frame(width: 39, height: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(space.title).font(.system(size: 13, weight: selected ? .semibold : .medium))
                    Text(rule.folderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "No folder yet")
                        .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if !rule.enabled && rule.folderPath != nil {
                    Image(systemName: "pause.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(selected ? Color.paperAccent.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(space.title), \(space.isVisible ? "visible" : "inactive"), \(rule.folderPath == nil ? "no folder" : "folder assigned")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14, *) {
            SettingsLink { Label("Settings", systemImage: "gearshape") }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        } else {
            Button { NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

private struct SpaceDetailView: View {
    @EnvironmentObject private var model: AppModel
    let space: DesktopSpace
    @ViewState private var galleryLimit = 60
    @ViewState private var thumbnailRefresh = 0
    @ViewState private var showRemoveConfirmation = false

    private var rule: SpaceRule { model.rule(for: space.id) }
    private var library: LibraryState { model.library(for: space.id) }
    private var image: URL? {
        guard let selected = rule.selectedImagePath else { return library.images.first }
        return library.images.first(where: { $0.path == selected })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if rule.folderPath == nil {
                    emptyState
                } else {
                    preview
                    folderCard
                    behaviorCard
                    gallery
                }
                footer
            }
            .padding(.horizontal, 34).padding(.top, 30).padding(.bottom, 24)
            .frame(maxWidth: 1080)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(!model.isWritable)
        .confirmationDialog("Remove folder assignment for \(space.title)?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            Button("Remove assignment", role: .destructive) { model.removeFolder(for: space.id) }
        } message: {
            Text("Your images and the last wallpaper applied will be kept.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Your Space. Your view.")
                    .font(.system(size: 11, weight: .medium)).tracking(0.3).foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(space.isVisible ? Color.paperAccent : .secondary).frame(width: 5, height: 5)
                    Text(space.isVisible ? "Currently visible" : "Inactive Space")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(space.isVisible ? Color.paperAccent : .secondary)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.paperAccent.opacity(space.isVisible ? 0.08 : 0.03), in: Capsule())
            }
            HStack(alignment: .firstTextBaseline) {
                Text(space.title).font(.system(size: 31, weight: .semibold, design: .rounded))
                Spacer()
                Text(space.display.name).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text("A separate image folder for this desktop.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            landscape
                .frame(height: 210)
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkle")
                        Text("Room for a fresh perspective")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9)).padding(20)
                }
            VStack(spacing: 14) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 32, weight: .light)).foregroundStyle(Color.paperAccent)
                Text("Make it yours with your images.")
                    .font(.system(size: 20, weight: .semibold))
                Text("Choose a folder with your favorite images.\nYou can include images in subfolders, too.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).lineSpacing(4)
                Button { model.chooseFolder(for: space.id) } label: {
                    Label("Choose image folder", systemImage: "folder")
                        .padding(.horizontal, 12).padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .padding(.top, 5)
                HStack(spacing: 18) {
                    Label("Search subfolders", systemImage: "folder.badge.gearshape")
                    Label("Local to your Mac", systemImage: "internaldrive")
                }
                .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 7)
            }
            .padding(.vertical, 32).frame(maxWidth: .infinity)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06)))
    }

    private var landscape: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(colors: [Color(red: 0.71, green: 0.81, blue: 0.78), Color(red: 0.91, green: 0.91, blue: 0.82)], startPoint: .top, endPoint: .bottom)
                Circle().fill(Color(red: 0.98, green: 0.95, blue: 0.77))
                    .frame(width: 72, height: 72).position(x: proxy.size.width * 0.74, y: 65)
                hill(width: proxy.size.width, height: proxy.size.height, offset: 0)
                    .fill(Color(red: 0.40, green: 0.61, blue: 0.56))
                hill(width: proxy.size.width, height: proxy.size.height, offset: 48)
                    .fill(Color(red: 0.22, green: 0.45, blue: 0.39))
                hill(width: proxy.size.width, height: proxy.size.height, offset: 92)
                    .fill(Color(red: 0.15, green: 0.32, blue: 0.29))
            }
        }
        .accessibilityHidden(true)
    }

    private func hill(width: CGFloat, height: CGFloat, offset: CGFloat) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: 120 + offset))
            p.addCurve(to: CGPoint(x: width, y: 100 + offset),
                       control1: CGPoint(x: width * 0.35, y: -10 + offset),
                       control2: CGPoint(x: width * 0.55, y: 210 - offset))
            p.addLine(to: CGPoint(x: width, y: height))
            p.addLine(to: CGPoint(x: 0, y: height))
            p.closeSubpath()
        }
    }

    private var preview: some View {
        HStack(alignment: .center, spacing: 22) {
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 11).fill(Color.black.opacity(0.8))
                ThumbnailView(url: image, maxPixelSize: 900, contentMode: rule.layout == .fit ? .fit : .fill,
                              refreshID: thumbnailRefresh, backgroundColor: rule.effectiveBackgroundColor.swiftUIColor)
                    .padding(5).clipShape(RoundedRectangle(cornerRadius: 10))
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { _ in Circle().fill(.white.opacity(0.5)).frame(width: 3, height: 3) }
                    Spacer()
                    Image(systemName: "wifi").font(.system(size: 6))
                }
                .foregroundStyle(.white.opacity(0.6)).padding(.horizontal, 12).padding(.top, 11)
            }
            .aspectRatio(16 / 10, contentMode: .fit)
            .frame(maxWidth: 320)
            .overlay(alignment: .bottom) {
                Capsule().fill(.white.opacity(0.3)).frame(width: 65, height: 4).padding(.bottom, 12)
            }
            .shadow(color: .black.opacity(0.12), radius: 12, y: 6)

            VStack(alignment: .leading, spacing: 11) {
                Text("IMAGE PREVIEW")
                    .font(.system(size: 9, weight: .semibold)).tracking(1.0).foregroundStyle(.secondary)
                Text(image?.deletingPathExtension().lastPathComponent ?? "Scanning images")
                    .font(.system(size: 17, weight: .medium)).lineLimit(2)
                if !space.isVisible && !model.directModeEnabled {
                    Text("Will be applied the next time you visit this Space.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else if let lastDate = rule.lastAppliedAt {
                    Text("Last applied: \(lastDate.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Button { model.nextImage(for: space.id) } label: {
                    Label("Next image", systemImage: "arrow.right")
                }
                .buttonStyle(.bordered).controlSize(.regular)
                .disabled(library.images.isEmpty || model.isPaused || !rule.enabled)
                Button(space.isVisible || model.directModeEnabled ? "Apply wallpaper" : "Queue for next visit") { model.applySelected(space.id) }
                    .buttonStyle(.link).font(.system(size: 11))
                    .disabled(library.images.isEmpty || model.isPaused || !rule.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20).card()
    }

    private var folderCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 12) {
                Image(systemName: "folder.fill").font(.system(size: 27)).foregroundStyle(Color.paperAccent.opacity(0.7))
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.folderPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Image folder")
                        .font(.system(size: 14, weight: .semibold))
                    Text(rule.folderPath ?? "").font(.system(size: 10)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle).help(rule.folderPath ?? "")
                }
                Spacer(minLength: 5)
                Button("Change…") { model.chooseFolder(for: space.id) }.controlSize(.small)
                Menu {
                    Button("Open in Finder") { model.revealFolder(space.id) }
                    Button("Rescan folder") { model.scan(space.id); thumbnailRefresh += 1 }
                    Divider()
                    Button("Remove assignment…", role: .destructive) { showRemoveConfirmation = true }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).frame(width: 18)
                .accessibilityLabel("Folder actions")
            }
            Divider()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Include subfolders", isOn: binding(\.recursive)).toggleStyle(.checkbox)
                        .font(.system(size: 12))
                    Text("Searches the selected folder recursively.")
                        .font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 20)
                }
                Spacer()
                if library.isScanning {
                    ProgressView().controlSize(.small)
                    Text("Scanning…").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Label("\(library.images.count) \(library.images.count == 1 ? "image" : "images")", systemImage: "photo.stack")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Color.paperAccent)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.paperAccent.opacity(0.07), in: Capsule())
                }
            }
            if let error = library.error {
                NoticeView(text: error, symbol: "exclamationmark.triangle", warning: true)
                Button("Scan again") { model.scan(space.id) }.font(.system(size: 11))
            } else if let notice = library.notice {
                NoticeView(text: notice, symbol: "info.circle", warning: false)
            }
        }
        .padding(18).card()
    }

    private var behaviorCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Wallpaper behavior", systemImage: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Enabled", isOn: binding(\.enabled)).toggleStyle(.switch).controlSize(.mini)
                    .font(.system(size: 11)).fixedSize()
            }
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("CHANGE IMAGE").font(.system(size: 9, weight: .medium)).tracking(0.7).foregroundStyle(.secondary)
                    Picker("Change image", selection: binding(\.rotation)) {
                        ForEach(RotationMode.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text("IMAGE SCALING").font(.system(size: 9, weight: .medium)).tracking(0.7).foregroundStyle(.secondary)
                    Picker("Image scaling", selection: binding(\.layout)) {
                        ForEach(ImageLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(maxWidth: .infinity)
                }
            }
            .disabled(!rule.enabled)
            if rule.layout == .fit {
                HStack {
                    ColorPicker("Background color: \(rule.resolvedBackgroundColor.displayName)", selection: Binding(
                        get: { rule.resolvedBackgroundColor.swiftUIColor },
                        set: { color in model.updateRule(space.id) { $0.backgroundColor = WallpaperColor(color) } }
                    ), supportsOpacity: false)
                    .font(.system(size: 12))
                    Button("Reset to Black") { model.updateRule(space.id) { $0.backgroundColor = .black } }
                        .buttonStyle(.link).font(.system(size: 11))
                }
                .disabled(!rule.enabled)
                Text("Fills the unused area beside or above the fitted image.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Toggle("Random order", isOn: binding(\.shuffle))
                    .toggleStyle(.checkbox).font(.system(size: 11))
                Spacer()
                Text("No immediate repeats").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .disabled(!rule.enabled)
        }
        .padding(18).card()
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("Images in folder").font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("Click to select").font(.system(size: 10)).foregroundStyle(.secondary)
                Button { model.scan(space.id); thumbnailRefresh += 1 } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(library.isScanning).help("Rescan folder")
                    .accessibilityLabel("Rescan folder")
            }
            if library.images.isEmpty && !library.isScanning && library.error == nil {
                VStack(spacing: 9) {
                    Image(systemName: "photo.on.rectangle.angled").font(.system(size: 24, weight: .light))
                    Text("No readable images found here yet.")
                    Text("Choose another folder or include subfolders.")
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary).font(.system(size: 12))
                .frame(maxWidth: .infinity).padding(.vertical, 30).card()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 130, maximum: 210), spacing: 12)], spacing: 14) {
                    ForEach(Array(library.images.prefix(galleryLimit)), id: \.self) { url in
                        imageTile(url)
                    }
                }
                if library.images.count > galleryLimit {
                    Button("Show more images (\(library.images.count - galleryLimit))") { galleryLimit += 60 }
                        .buttonStyle(.bordered).frame(maxWidth: .infinity)
                }
            }
        }
    }

    private func imageTile(_ url: URL) -> some View {
        let selected = rule.selectedImagePath == url.path
        return Button { model.selectImage(url, for: space.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                ThumbnailView(url: url, refreshID: thumbnailRefresh)
                    .aspectRatio(1.6, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Color.paperAccent : .primary.opacity(0.05), lineWidth: selected ? 2.5 : 1))
                    .overlay(alignment: .bottomTrailing) {
                        if selected {
                            Image(systemName: "checkmark.circle.fill")
                                .symbolRenderingMode(.palette).foregroundStyle(.white, Color.paperAccent)
                                .font(.system(size: 19)).padding(7)
                        }
                    }
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 10, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? Color.paperAccent : .secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!rule.enabled)
        .help(url.lastPathComponent)
        .accessibilityLabel("\(url.lastPathComponent)\(selected ? ", selected" : "")")
    }

    private var footer: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle").font(.system(size: 10))
            Text(model.directModeEnabled
                 ? "Direct mode also updates inactive desktop Spaces. The wallpaper may briefly flicker when changing images. Full-screen Spaces remain unchanged."
                 : "Inactive Spaces are updated the next time you visit them. Full-screen Spaces remain unchanged.")
                .font(.system(size: 10)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.tertiary)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SpaceRule, Value>) -> Binding<Value> {
        Binding(get: { model.rule(for: space.id)[keyPath: keyPath] },
                set: { value in model.updateRule(space.id) { $0[keyPath: keyPath] = value } })
    }
}

struct NoticeView: View {
    let text: String
    let symbol: String
    let warning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(warning ? Color.orange : .secondary)
        .padding(10)
        .background((warning ? Color.orange : Color.secondary).opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

private extension View {
    func card() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
    }
}
