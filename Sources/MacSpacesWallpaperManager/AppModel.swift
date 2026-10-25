import AppKit
import Combine
import ServiceManagement
import WallpaperCore

struct LibraryState {
    var images: [URL] = []
    var isScanning = false
    var hasScanned = false
    var notice: String?
    var error: String?
}

private struct PreparedDirectChange: Sendable {
    let spaceID: String
    let change: DirectWallpaperChange
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var spaces: [DesktopSpace] = []
    @Published private(set) var configuration = AppConfiguration()
    @Published private(set) var libraries: [String: LibraryState] = [:]
    @Published var selectedSpaceID: String?
    @Published private(set) var selectedSpaceIDs: Set<String> = []
    @Published private(set) var isSelectingMultipleSpaces = false
    @Published private(set) var spaceError: String?
    @Published private(set) var persistenceError: String?
    @Published var actionError: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var isApplyingDirect = false
    @Published private(set) var lastDirectBackup: DirectWallpaperBackup?
    @Published var directModeNotice: String?

    private let catalog = SpaceCatalog()
    private let store = ConfigurationStore()
    private var folderAccess: [String: URL] = [:]
    private var scanTasks: [String: Task<Void, Never>] = [:]
    private var scanTokens: [String: UUID] = [:]
    private var pendingAdvance: Set<String> = []
    private var pendingApply: Set<String> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var applicationObservers: [NSObjectProtocol] = []
    private var refreshTask: Task<Void, Never>?
    private var timer: Timer?
    private var started = false
    private let directService = DirectWallpaperService()
    private var directTask: Task<Void, Never>?
    private var directQueue: [String: PreparedDirectChange] = [:]
    private var directInFlight: [String: PreparedDirectChange] = [:]

    var selectedSpace: DesktopSpace? { spaces.first { $0.id == selectedSpaceID } }
    var selectedSpaces: [DesktopSpace] { spaces.filter { selectedSpaceIDs.contains($0.id) } }
    var configuredCount: Int {
        spaces.filter { rule(for: $0.id).folderPath != nil && rule(for: $0.id).enabled }.count
    }
    var isPaused: Bool { configuration.paused }
    var isWritable: Bool { persistenceError == nil }
    var directModeEnabled: Bool { configuration.directWallpaperMode }
    var canRestoreDirectBackup: Bool { lastDirectBackup != nil && lastDirectBackup?.restored == false && !isApplyingDirect }
    var directModeAvailable: Bool {
        if #available(macOS 14, *) {
            return FileManager.default.isReadableFile(atPath: DirectWallpaperWriter().storeURL.path)
        }
        return false
    }

    func start() {
        guard !started else { return }
        started = true
        do { configuration = try store.load() }
        catch { persistenceError = "Die Einstellungen konnten nicht geladen werden: \(error.localizedDescription) Die vorhandene Datei bleibt erhalten." }
        if directModeEnabled && !directModeAvailable {
            configuration.directWallpaperMode = false
            directModeNotice = "Der Direktmodus ist auf diesem Mac nicht verfügbar. Der Standardmodus bleibt aktiv."
            save()
        }
        refreshDirectBackup()
        updateLoginStatus()
        refreshSpaces()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.screensDidWakeNotification, NSWorkspace.didMountNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
        for name in [NSApplication.didChangeScreenParametersNotification, NSApplication.didBecomeActiveNotification] {
            applicationObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        timer?.tolerance = 3
    }

    func stop() {
        refreshTask?.cancel()
        directTask?.cancel()
        scanTasks.values.forEach { $0.cancel() }
        timer?.invalidate()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        applicationObservers.forEach { NotificationCenter.default.removeObserver($0) }
        folderAccess.values.forEach { $0.stopAccessingSecurityScopedResource() }
    }

    func rule(for id: String) -> SpaceRule { configuration.rules[id] ?? SpaceRule() }
    func library(for id: String) -> LibraryState { libraries[id] ?? LibraryState() }

    func currentImageURL(for space: DesktopSpace) -> URL? {
        guard space.isVisible, let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == space.display.displayID
        }) else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    func refreshSpaces() {
        let previouslyVisible = Set(spaces.filter(\.isVisible).map(\.id))
        do {
            spaces = try catalog.read()
            spaceError = nil
        } catch {
            spaces = [] // Never apply a rule using a stale Space identity.
            spaceError = error.localizedDescription
            return
        }
        if !spaces.contains(where: { $0.id == selectedSpaceID }) {
            selectedSpaceID = spaces.first(where: \.isVisible)?.id ?? spaces.first?.id
        }
        selectedSpaceIDs.formIntersection(Set(spaces.map(\.id)))
        guard isWritable else { return }
        for space in spaces {
            let rule = rule(for: space.id)
            guard rule.folderPath != nil else { continue }
            let entered = space.isVisible && !previouslyVisible.contains(space.id)
            if entered && rule.rotation == .onSpaceChange && !isPaused && rule.enabled {
                pendingAdvance.insert(space.id)
            }
            if libraries[space.id]?.hasScanned != true && libraries[space.id]?.isScanning != true {
                scan(space.id)
            } else if space.isVisible || directModeEnabled {
                applyWallpaper(space.id)
            }
        }
    }

    func selectSpace(_ id: String) {
        guard spaces.contains(where: { $0.id == id }) else { return }
        if isSelectingMultipleSpaces {
            if selectedSpaceIDs.contains(id) { selectedSpaceIDs.remove(id) }
            else { selectedSpaceIDs.insert(id) }
        }
        selectedSpaceID = id
    }

    func toggleMultipleSelection() {
        isSelectingMultipleSpaces.toggle()
        if isSelectingMultipleSpaces {
            selectedSpaceIDs = selectedSpaceID.map { Set([$0]) } ?? []
        } else {
            if let first = selectedSpaces.first { selectedSpaceID = first.id }
            selectedSpaceIDs.removeAll()
        }
    }

    func selectAllSpaces(on displayID: String? = nil) {
        selectedSpaceIDs.formUnion(spaces.filter { displayID == nil || $0.display.id == displayID }.map(\.id))
    }

    func clearSpaceSelection() { selectedSpaceIDs.removeAll() }

    func chooseBulkFolder(_ completion: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Gemeinsamen Bilderordner auswählen"
        panel.message = "Der Ordner wird nach „Anwenden“ den ausgewählten Spaces zugeordnet."
        panel.prompt = "Ordner auswählen"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            completion(url)
        }
    }

    @discardableResult
    func applyBulkChanges(_ requestedChanges: SpaceRuleChanges, folderURL: URL? = nil) -> Int {
        guard isWritable, !isApplyingDirect else { return 0 }
        let ids = selectedSpaceIDs.intersection(Set(spaces.map(\.id)))
        guard !ids.isEmpty else { return 0 }
        var changes = requestedChanges
        do {
            if let folderURL {
                let access = folderURL.startAccessingSecurityScopedResource()
                defer { if access { folderURL.stopAccessingSecurityScopedResource() } }
                let bookmark = try folderURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                changes.folder = WallpaperFolder(path: folderURL.path, bookmark: bookmark)
            }
            guard !changes.isEmpty else { return 0 }
            let previous = configuration.rules
            configuration.rules = changes.applying(to: previous, spaceIDs: ids)
            save()
            guard isWritable else { return 0 }
            for id in ids {
                let old = previous[id] ?? SpaceRule()
                let updated = rule(for: id)
                if changes.folder != nil || old.recursive != updated.recursive {
                    directQueue.removeValue(forKey: id)
                    scan(id)
                } else if old.layout != updated.layout || old.effectiveBackgroundColor != updated.effectiveBackgroundColor
                            || (!old.enabled && updated.enabled) {
                    pendingApply.insert(id)
                    applyWallpaper(id)
                }
            }
            return ids.count
        } catch {
            actionError = "Die gemeinsamen Einstellungen konnten nicht übernommen werden: \(error.localizedDescription)"
            return 0
        }
    }

    private func scheduleRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            // Wait for the Space transition to settle; repeated notifications are coalesced.
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshSpaces()
        }
    }

    func chooseFolder(for id: String) {
        guard isWritable else { return }
        let panel = NSOpenPanel()
        panel.title = "Bilderordner auswählen"
        panel.message = "Dieser Ordner wird nur dem ausgewählten Desktop zugeordnet."
        panel.prompt = "Ordner verwenden"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if let folder = rule(for: id).folderPath { panel.directoryURL = URL(fileURLWithPath: folder) }
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in self?.assignFolder(url, to: id) }
        }
    }

    func assignFolder(_ url: URL, to id: String) {
        guard isWritable else { return }
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            var updated = rule(for: id)
            updated.folderBookmark = bookmark
            updated.folderPath = url.path
            updated.selectedImagePath = nil
            updated.lastAppliedImagePath = nil
            updated.lastAppliedAt = nil
            updated.lastAppliedBackgroundColor = nil
            updated.enabled = true
            configuration.rules[id] = updated
            save()
            scan(id)
        } catch { actionError = "Der Ordner konnte nicht zugeordnet werden: \(error.localizedDescription)" }
    }

    func updateRule(_ id: String, _ update: (inout SpaceRule) -> Void) {
        guard isWritable else { return }
        var updated = rule(for: id)
        let original = updated
        update(&updated)
        configuration.rules[id] = updated
        save()
        if original.recursive != updated.recursive {
            scan(id)
        } else if original.layout != updated.layout || original.effectiveBackgroundColor != updated.effectiveBackgroundColor
                    || (!original.enabled && updated.enabled) {
            pendingApply.insert(id)
            applyWallpaper(id)
        }
    }

    func removeFolder(for id: String) {
        guard isWritable else { return }
        scanTasks[id]?.cancel()
        scanTasks[id] = nil
        scanTokens[id] = nil
        folderAccess.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
        libraries.removeValue(forKey: id)
        pendingAdvance.remove(id)
        pendingApply.remove(id)
        directQueue.removeValue(forKey: id)
        configuration.rules.removeValue(forKey: id)
        save()
    }

    func selectImage(_ image: URL, for id: String) {
        guard isWritable, library(for: id).images.contains(image) else { return }
        updateRule(id) { $0.selectedImagePath = image.path }
        pendingAdvance.remove(id)
        pendingApply.insert(id)
        applyWallpaper(id)
    }

    func nextImage(for id: String) {
        guard isWritable else { return }
        let rule = rule(for: id)
        guard let image = ImageSelection.next(in: library(for: id).images,
                                              after: rule.selectedImagePath ?? rule.lastAppliedImagePath,
                                              shuffle: rule.shuffle) else { return }
        selectImage(image, for: id)
    }

    func nextVisibleImages() {
        refreshSpaces()
        for space in spaces where space.isVisible && rule(for: space.id).enabled {
            nextImage(for: space.id)
        }
    }

    func applySelected(_ id: String) {
        pendingAdvance.remove(id)
        pendingApply.insert(id)
        applyWallpaper(id)
    }

    func togglePaused() {
        guard isWritable else { return }
        configuration.paused.toggle()
        save()
        if !isPaused { refreshSpaces() }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            updateLoginStatus()
        } catch {
            updateLoginStatus()
            actionError = "Die Anmeldung konnte nicht geändert werden: \(error.localizedDescription) Starte Mac Spaces Wallpaper Manager dazu aus dem Programme-Ordner."
        }
    }

    func updateLoginStatus() {
        launchAtLogin = [.enabled, .requiresApproval].contains(SMAppService.mainApp.status)
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func showConfigurationFile() {
        NSWorkspace.shared.selectFile(store.url.path, inFileViewerRootedAtPath: store.url.deletingLastPathComponent().path)
    }

    func revealFolder(_ id: String) {
        if let folder = rule(for: id).folderPath {
            NSWorkspace.shared.open(URL(fileURLWithPath: folder, isDirectory: true))
        }
    }

    func scan(_ id: String) {
        guard isWritable, let folderPath = rule(for: id).folderPath else { return }
        scanTasks[id]?.cancel()
        let token = UUID()
        scanTokens[id] = token
        libraries[id, default: LibraryState()].isScanning = true
        libraries[id]?.error = nil
        let recursive = rule(for: id).recursive
        let bookmark = rule(for: id).folderBookmark
        scanTasks[id] = Task { [weak self] in
            // Each scan owns its access lifetime, so cancelling/replacing a scan cannot revoke another one's access.
            var stale = false
            let folder: URL
            do {
                if let bookmark {
                    folder = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                     relativeTo: nil, bookmarkDataIsStale: &stale)
                } else {
                    folder = URL(fileURLWithPath: folderPath, isDirectory: true)
                }
                let access = folder.startAccessingSecurityScopedResource()
                defer { if access { folder.stopAccessingSecurityScopedResource() } }
                if stale, let renewed = try? folder.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    self?.configuration.rules[id]?.folderBookmark = renewed
                    self?.configuration.rules[id]?.folderPath = folder.path
                    self?.save()
                }
                let worker = Task.detached(priority: .userInitiated) {
                    try ImageScanner.scan(folder: folder, recursive: recursive)
                }
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                guard !Task.isCancelled, let self, self.scanTokens[id] == token else { return }
                // Retain access for thumbnails and wallpaper changes until the folder is replaced or the app exits.
                self.folderAccess.removeValue(forKey: id)?.stopAccessingSecurityScopedResource()
                if folder.startAccessingSecurityScopedResource() { self.folderAccess[id] = folder }
                var notices: [String] = []
                if result.skippedCount > 0 { notices.append("\(result.skippedCount) nicht lesbare Bilddatei(en) übersprungen") }
                if result.unreadableDirectoryCount > 0 { notices.append("\(result.unreadableDirectoryCount) Ordner nicht lesbar") }
                self.libraries[id] = LibraryState(images: result.images, hasScanned: true,
                                                  notice: notices.isEmpty ? nil : notices.joined(separator: " · "))
                if !result.images.contains(where: { $0.path == self.rule(for: id).selectedImagePath }) {
                    self.configuration.rules[id]?.selectedImagePath = ImageSelection.next(
                        in: result.images, after: self.rule(for: id).lastAppliedImagePath,
                        shuffle: self.rule(for: id).shuffle
                    )?.path
                    self.save()
                }
                self.scanTasks[id] = nil
                self.applyWallpaper(id)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, let self, self.scanTokens[id] == token else { return }
                self.libraries[id] = LibraryState(hasScanned: true, error: error.localizedDescription)
                self.scanTasks[id] = nil
            }
        }
    }

    private func tick() {
        // Read again before every timer-driven change, including after display reconnects and sleep.
        refreshSpaces()
    }

    private func applyWallpaper(_ id: String) {
        guard !isPaused, isWritable, spaceError == nil,
              let space = spaces.first(where: { $0.id == id && ($0.isVisible || directModeEnabled) }),
              let screen = NSScreen.screens.first(where: {
                  ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == space.display.displayID
              }), let state = libraries[id], !state.isScanning, !state.images.isEmpty else { return }
        var rule = rule(for: id)
        guard rule.enabled else { return }
        // Recheck immediately before writing. A completed background scan can race with a Space switch.
        guard let current = try? catalog.read(), current.contains(where: { $0.id == id && ($0.isVisible || directModeEnabled) }) else { return }
        if directModeEnabled,
           let queued = directQueue[id] ?? directInFlight[id],
           queued.change.imageURL.path == rule.selectedImagePath, queued.change.layout == rule.layout,
           queued.change.backgroundColor == (rule.layout == .fit ? rule.resolvedBackgroundColor : nil) { return }
        let hasPendingSelection = rule.selectedImagePath != nil && rule.selectedImagePath != rule.lastAppliedImagePath
        let shouldAdvance = !hasPendingSelection && !pendingApply.contains(id)
            && (pendingAdvance.contains(id) || ImageSelection.isDue(rule: rule, now: Date()))
        var image = rule.selectedImagePath.flatMap { selected in state.images.first { $0.path == selected } }
        if image == nil || shouldAdvance {
            image = ImageSelection.next(in: state.images, after: rule.lastAppliedImagePath, shuffle: rule.shuffle)
        }
        guard let image else { return }
        if directModeEnabled {
            if !shouldAdvance && !pendingApply.contains(id)
                && rule.lastAppliedImagePath == image.path && rule.lastAppliedLayout == rule.layout
                && rule.lastAppliedBackgroundColor == rule.effectiveBackgroundColor
                && rule.lastAppliedWithDirectMode == true { return }
            rule.selectedImagePath = image.path
            configuration.rules[id] = rule
            directQueue[id] = PreparedDirectChange(spaceID: id, change: DirectWallpaperChange(
                spaceUUID: space.uuid, displayUUID: space.display.id, imageURL: image, layout: rule.layout,
                backgroundColor: rule.layout == .fit ? rule.resolvedBackgroundColor : nil
            ))
            scheduleDirectWrite()
            return
        }
        guard !isApplyingDirect else { return }
        let alreadyApplied = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL == image
        if alreadyApplied && !shouldAdvance && !pendingApply.contains(id)
            && rule.lastAppliedImagePath == image.path && rule.lastAppliedLayout == rule.layout
            && rule.lastAppliedBackgroundColor == rule.effectiveBackgroundColor
            && rule.lastAppliedWithDirectMode != true { return }

        let scaling: NSImageScaling
        switch rule.layout {
        case .fill, .fit: scaling = .scaleProportionallyUpOrDown
        case .stretch: scaling = .scaleAxesIndependently
        case .center: scaling = .scaleNone
        }
        do {
            try NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [
                .imageScaling: scaling.rawValue,
                .allowClipping: rule.layout == .fill,
                .fillColor: rule.effectiveBackgroundColor.nsColor
            ])
            rule.selectedImagePath = image.path
            rule.lastAppliedImagePath = image.path
            rule.lastAppliedLayout = rule.layout
            rule.lastAppliedBackgroundColor = rule.effectiveBackgroundColor
            rule.lastAppliedWithDirectMode = false
            rule.lastAppliedAt = Date()
            configuration.rules[id] = rule
            pendingAdvance.remove(id)
            pendingApply.remove(id)
            libraries[id]?.error = nil
            save()
        } catch {
            libraries[id]?.error = "Das Hintergrundbild konnte nicht gesetzt werden: \(error.localizedDescription)"
        }
    }

    func setDirectMode(_ enabled: Bool) {
        guard isWritable, !isApplyingDirect else { return }
        guard !enabled || directModeAvailable else {
            actionError = "Der Direktmodus benötigt macOS 14 oder neuer und eine lesbare macOS-Hintergrunddatei."
            return
        }
        directTask?.cancel()
        directQueue.removeAll()
        configuration.directWallpaperMode = enabled
        directModeNotice = nil
        if enabled {
            for space in spaces where rule(for: space.id).folderPath != nil { pendingApply.insert(space.id) }
        }
        save()
        refreshSpaces()
    }

    func refreshDirectBackup() {
        Task { [weak self] in
            guard let self else { return }
            self.lastDirectBackup = await self.directService.latestBackup()
        }
    }

    func showDirectBackups() {
        let directory = lastDirectBackup?.directory ?? DirectWallpaperWriter().backupsDirectory
        NSWorkspace.shared.open(directory)
    }

    func restoreDirectBackup() {
        guard isWritable, canRestoreDirectBackup else { return }
        directTask?.cancel()
        directQueue.removeAll()
        configuration.paused = true
        configuration.directWallpaperMode = false
        save()
        isApplyingDirect = true
        directTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.lastDirectBackup = try await self.directService.restoreLatest()
                for id in Array(self.configuration.rules.keys) {
                    self.configuration.rules[id]?.lastAppliedWithDirectMode = nil
                    self.configuration.rules[id]?.lastAppliedImagePath = nil
                    self.configuration.rules[id]?.lastAppliedAt = nil
                    self.configuration.rules[id]?.lastAppliedBackgroundColor = nil
                }
                self.save()
                self.directModeNotice = "Die letzte Direktmodus-Änderung wurde zurückgenommen. Die Automatik bleibt pausiert, bis du sie fortsetzt."
            } catch {
                self.directModeNotice = "Die Wiederherstellung wurde abgebrochen: \(error.localizedDescription) Die Automatik bleibt pausiert."
            }
            self.isApplyingDirect = false
        }
    }

    private func scheduleDirectWrite() {
        guard !isApplyingDirect else { return }
        directTask?.cancel()
        directTask = Task { [weak self] in
            // Coalesce scanner completions and changes across multiple displays into one restart.
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushDirectWrites()
        }
    }

    private func flushDirectWrites() async {
        guard directModeEnabled, !isPaused, isWritable, !isApplyingDirect,
              let current = try? catalog.read() else { directQueue.removeAll(); return }
        let validIDs = Set(current.map(\.id))
        let prepared = directQueue.values.filter {
            validIDs.contains($0.spaceID) && rule(for: $0.spaceID).enabled
                && rule(for: $0.spaceID).selectedImagePath == $0.change.imageURL.path
                && rule(for: $0.spaceID).layout == $0.change.layout
                && (rule(for: $0.spaceID).layout == .fit ? rule(for: $0.spaceID).resolvedBackgroundColor : nil) == $0.change.backgroundColor
        }
        directQueue.removeAll()
        guard !prepared.isEmpty else { return }
        isApplyingDirect = true
        directInFlight = Dictionary(uniqueKeysWithValues: prepared.map { ($0.spaceID, $0) })
        do {
            if let backup = try await directService.apply(prepared.map(\.change)) { lastDirectBackup = backup }
            for item in prepared where configuration.rules[item.spaceID] != nil {
                configuration.rules[item.spaceID]?.lastAppliedImagePath = item.change.imageURL.path
                configuration.rules[item.spaceID]?.lastAppliedLayout = item.change.layout
                configuration.rules[item.spaceID]?.lastAppliedBackgroundColor = item.change.backgroundColor ?? .black
                configuration.rules[item.spaceID]?.lastAppliedWithDirectMode = true
                configuration.rules[item.spaceID]?.lastAppliedAt = Date()
                if rule(for: item.spaceID).selectedImagePath == item.change.imageURL.path,
                   rule(for: item.spaceID).layout == item.change.layout,
                   rule(for: item.spaceID).effectiveBackgroundColor == (item.change.backgroundColor ?? .black) {
                    pendingApply.remove(item.spaceID)
                    pendingAdvance.remove(item.spaceID)
                }
                libraries[item.spaceID]?.error = nil
            }
            save()
        } catch {
            configuration.directWallpaperMode = false
            configuration.paused = true
            directQueue.removeAll()
            directModeNotice = "Der Direktmodus wurde deaktiviert und die Automatik pausiert: \(error.localizedDescription) Du kannst anschließend im Standardmodus fortfahren."
            lastDirectBackup = await directService.latestBackup()
            save()
        }
        directInFlight.removeAll()
        isApplyingDirect = false
        if !directQueue.isEmpty && directModeEnabled && !isPaused { scheduleDirectWrite() }
    }

    private func save() {
        guard isWritable else { return }
        do { try store.save(configuration) }
        catch { persistenceError = "Die Einstellungen konnten nicht gespeichert werden: \(error.localizedDescription)" }
    }
}
