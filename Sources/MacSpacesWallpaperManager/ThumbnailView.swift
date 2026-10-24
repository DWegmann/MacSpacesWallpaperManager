import AppKit
import ImageIO
import SwiftUI

// Images are immutable after decoding; NSCache synchronizes shared cache access on macOS 13 as well.
private struct ThumbnailResult: @unchecked Sendable {
    let image: NSImage?
}

private final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    let images = NSCache<NSString, NSImage>()

    private init() {
        images.totalCostLimit = 90 * 1_024 * 1_024
        images.countLimit = 180
    }

    func load(_ url: URL, size: Int) -> NSImage? {
        let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)|\(modified)|\(size)" as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: size,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        images.setObject(thumbnail, forKey: key, cost: image.bytesPerRow * image.height)
        return thumbnail
    }
}

struct ThumbnailView: View {
    let url: URL?
    var maxPixelSize = 400
    var contentMode: ContentMode = .fill
    var refreshID = 0
    var backgroundColor: Color = Color(nsColor: .controlBackgroundColor)
    @ViewState private var image: NSImage?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundColor
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: "\(url?.path ?? "")|\(maxPixelSize)|\(refreshID)") {
            image = nil
            guard let url else { return }
            let size = maxPixelSize
            let worker = Task.detached(priority: .utility) {
                ThumbnailResult(image: ThumbnailCache.shared.load(url, size: size))
            }
            let thumbnail = await worker.value
            guard !Task.isCancelled else { return }
            image = thumbnail.image
        }
        .accessibilityHidden(true)
    }
}
