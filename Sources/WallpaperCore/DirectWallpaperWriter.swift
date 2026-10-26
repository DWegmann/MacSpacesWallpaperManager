import Darwin
import Foundation
import ImageIO

public struct DirectWallpaperBackup: Codable, Equatable, Sendable {
    public let directory: URL
    public let createdAt: Date
    public let changeCount: Int
    public var restored: Bool
}

/// All filesystem/process operations are synchronous here; the app runs this writer on a dedicated actor.
public final class DirectWallpaperWriter {
    public let storeURL: URL
    public let backupsDirectory: URL
    private let agent: WallpaperAgentControlling

    public init(storeURL: URL? = nil, backupsDirectory: URL? = nil,
                agent: WallpaperAgentControlling = WallpaperAgentControl()) {
        self.storeURL = storeURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
        self.backupsDirectory = backupsDirectory ?? ConfigurationStore().url.deletingLastPathComponent()
            .appendingPathComponent("WallpaperBackups", isDirectory: true)
        self.agent = agent
    }

    public func preview(_ changes: [DirectWallpaperChange]) throws -> DirectWallpaperPatch {
        try DirectWallpaperStore.patch(readStore(), changes: changes)
    }

    public func latestBackup() -> DirectWallpaperBackup? {
        guard let data = try? Data(contentsOf: backupsDirectory.appendingPathComponent("latest.plist")),
              let backup = try? PropertyListDecoder().decode(DirectWallpaperBackup.self, from: data),
              backup.directory.deletingLastPathComponent().standardizedFileURL == backupsDirectory.standardizedFileURL else { return nil }
        return backup
    }

    @discardableResult
    public func apply(_ changes: [DirectWallpaperChange]) throws -> DirectWallpaperBackup? {
        guard !changes.isEmpty else { return nil }
        for change in changes {
            guard change.imageURL.isFileURL,
                  (try? change.imageURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  let source = CGImageSourceCreateWithURL(change.imageURL as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) > 0,
                  CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil else { throw DirectWallpaperError.invalidImage }
        }
        // Validate before signaling any system process, and avoid restarts for identical selections.
        guard try !preview(changes).undo.isEmpty else { return nil }
        return try withLock {
            try agent.suspend()
            defer { agent.resume() }
            let start = ProcessInfo.processInfo.systemUptime
            let original = try readStore()
            let patch = try DirectWallpaperStore.patch(original, changes: changes)
            if patch.undo.isEmpty { return nil }
            let backup = try makeBackup(original: original, patch: patch)
            try commit(original: original, patch: patch, backup: backup, started: start)
            pruneBackups(keeping: backup.directory)
            return backup
        }
    }

    @discardableResult
    public func restoreLatest() throws -> DirectWallpaperBackup {
        try withLock {
            guard var backup = latestBackup(), !backup.restored else { throw DirectWallpaperError.noBackup }
            let undoData = try Data(contentsOf: backup.directory.appendingPathComponent("undo.plist"))
            let undo = try PropertyListDecoder().decode([DirectWallpaperUndo].self, from: undoData)
            // Detect an external change before stopping the agent, then check again once it is paused.
            _ = try DirectWallpaperStore.restoration(readStore(), undo: undo)
            try agent.suspend()
            defer { agent.resume() }
            let start = ProcessInfo.processInfo.systemUptime
            let original = try readStore()
            let patch = try DirectWallpaperStore.restoration(original, undo: undo)
            try writePrivate(original, to: backup.directory.appendingPathComponent("before-restore.plist"))
            try commit(original: original, patch: patch, backup: backup, started: start, restoring: true)
            backup.restored = true
            try saveLatest(backup)
            return backup
        }
    }

    private func commit(original: Data, patch: DirectWallpaperPatch,
                        backup: DirectWallpaperBackup, started: TimeInterval, restoring: Bool = false) throws {
        var wrote = false
        do {
            // The independent resume watchdog has a 3-second deadline. Abort before writing if preparation was slow.
            guard ProcessInfo.processInfo.systemUptime - started < 1.5,
                  try readStore() == original else { throw DirectWallpaperError.concurrentChange }
            try writeStore(patch.data) { wrote = true }
            try agent.reload()
            Thread.sleep(forTimeInterval: 0.2)
            guard DirectWallpaperStore.containsChanges(try readStore(), undo: patch.undo) else {
                throw DirectWallpaperError.reloadFailed
            }
        } catch {
            guard wrote else {
                if !restoring {
                    var unused = backup
                    unused.restored = true
                    try? saveLatest(unused)
                }
                throw error
            }
            let reason = error.localizedDescription
            do {
                // A failed restart may leave no running agent; still restore the file for its next launch.
                let suspended = (try? agent.suspend()) != nil
                defer { agent.resume() }
                let current = try readStore()
                let restored = current == patch.data || current == original
                    ? original : try DirectWallpaperStore.restoring(current, undo: patch.undo)
                guard try readStore() == current else { throw DirectWallpaperError.concurrentChange }
                try writeStore(restored)
                if suspended { try agent.reload() }
                var recovered = backup
                recovered.restored = !restoring
                try saveLatest(recovered)
                throw DirectWallpaperError.transactionFailed(reason, "The change was undone. Backup: \(backup.directory.path)")
            } catch let recoveryError as DirectWallpaperError {
                if case .transactionFailed = recoveryError { throw recoveryError }
                throw DirectWallpaperError.transactionFailed(reason,
                    "Automatic recovery could not be completed: \(recoveryError.localizedDescription) Backup: \(backup.directory.path)")
            } catch {
                throw DirectWallpaperError.transactionFailed(reason,
                    "Automatic recovery could not be completed: \(error.localizedDescription) Backup: \(backup.directory.path)")
            }
        }
    }

    private func readStore() throws -> Data {
        let values = try storeURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? 0) < 20 * 1_024 * 1_024 else { throw DirectWallpaperError.unsupportedStore }
        return try Data(contentsOf: storeURL)
    }

    private func makeBackup(original: Data, patch: DirectWallpaperPatch) throws -> DirectWallpaperBackup {
        let directory = backupsDirectory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try writePrivate(original, to: directory.appendingPathComponent("before.plist"))
        try writePrivate(patch.data, to: directory.appendingPathComponent("after.plist"))
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try writePrivate(encoder.encode(patch.undo), to: directory.appendingPathComponent("undo.plist"))
        let backup = DirectWallpaperBackup(directory: directory, createdAt: Date(), changeCount: patch.undo.count, restored: false)
        try saveLatest(backup)
        return backup
    }

    private func writeStore(_ data: Data, didWrite: () -> Void = {}) throws {
        let permissions = try FileManager.default.attributesOfItem(atPath: storeURL.path)[.posixPermissions]
        try data.write(to: storeURL, options: .atomic)
        didWrite()
        if let permissions { try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: storeURL.path) }
    }

    private func saveLatest(_ backup: DirectWallpaperBackup) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try writePrivate(encoder.encode(backup), to: backupsDirectory.appendingPathComponent("latest.plist"))
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func pruneBackups(keeping latest: URL) {
        // Only recognize this writer's own snapshot directories; retain the latest ten to bound disk use.
        guard let contents = try? FileManager.default.contentsOfDirectory(at: backupsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]) else { return }
        let snapshots = contents.compactMap { url -> (URL, Date)? in
            let name = url.lastPathComponent.split(separator: "-", maxSplits: 1)
            guard name.count == 2, Int(name[0]) != nil, UUID(uuidString: String(name[1])) != nil,
                  let attributes = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .creationDateKey]),
                  attributes.isDirectory == true, attributes.isSymbolicLink != true,
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("undo.plist").path),
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("before.plist").path) else { return nil }
            return (url, attributes.creationDate ?? .distantPast)
        }.sorted { $0.1 > $1.1 }
        let older = snapshots.filter { $0.0.lastPathComponent != latest.lastPathComponent }.dropFirst(9)
        for item in older { try? FileManager.default.removeItem(at: item.0) }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = open(backupsDirectory.appendingPathComponent("writer.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw DirectWallpaperError.busy }
        defer { flock(descriptor, LOCK_UN) }
        return try operation()
    }
}

public actor DirectWallpaperService {
    private let writer = DirectWallpaperWriter()
    public init() {}
    public func latestBackup() -> DirectWallpaperBackup? { writer.latestBackup() }
    public func apply(_ changes: [DirectWallpaperChange]) throws -> DirectWallpaperBackup? { try writer.apply(changes) }
    public func restoreLatest() throws -> DirectWallpaperBackup { try writer.restoreLatest() }
}
