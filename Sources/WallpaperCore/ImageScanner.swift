import Foundation
import ImageIO

public struct ScanResult: Sendable {
    public let images: [URL]
    public let skippedCount: Int
    public let unreadableDirectoryCount: Int
}

public enum ScanError: LocalizedError {
    case unavailableFolder
    public var errorDescription: String? {
        "The folder is unavailable or cannot be read. Please select it again."
    }
}

public enum ImageScanner {
    // A cheap candidate filter; ImageIO, rather than Launch Services, validates actual file contents.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "jpe", "jfif", "png", "heic", "heif", "hif", "avif", "tif", "tiff",
        "gif", "bmp", "dib", "webp", "jp2", "j2k", "jpf", "jpx", "jpm", "mj2", "ico", "icns",
        "pict", "pct", "pic", "psd", "exr", "hdr", "tga", "sgi", "pntg", "qtif",
        "dng", "raw", "cr2", "cr3", "nef", "nrw", "arw", "orf", "raf", "rw2", "pef", "srw"
    ]

    /// Hidden items, packages and symlinks are deliberately excluded. Symlinked folders cannot form cycles.
    public static func scan(folder: URL, recursive: Bool) throws -> ScanResult {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey])
        guard values.isDirectory == true, values.isReadable == true else { throw ScanError.unavailableFolder }
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recursive { options.insert(.skipsSubdirectoryDescendants) }
        var unreadable = 0
        guard let enumerator = FileManager.default.enumerator(
            at: folder, includingPropertiesForKeys: Array(keys), options: options,
            errorHandler: { _, _ in unreadable += 1; return true }
        ) else { throw ScanError.unavailableFolder }

        var images: [URL] = []
        var skipped = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            guard let resource = try? url.resourceValues(forKeys: keys) else { skipped += 1; continue }
            if resource.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard resource.isRegularFile == true else { continue }
            let suffix = url.pathExtension.lowercased()
            guard suffix.isEmpty || imageExtensions.contains(suffix) else { continue }
            // Verify metadata without decoding every full-resolution image into memory.
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  CGImageSourceGetCount(source) > 0,
                  let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  (metadata[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0 > 0,
                  (metadata[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0 > 0 else {
                skipped += 1
                continue
            }
            images.append(url.standardizedFileURL)
        }
        images.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return ScanResult(images: images, skippedCount: skipped, unreadableDirectoryCount: unreadable)
    }
}
