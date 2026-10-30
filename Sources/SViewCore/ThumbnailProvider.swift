import CoreGraphics
import Foundation

/// Small decodes for the thumbnail strip (SV-206), in a cache of their own
/// so browsing thumbnails never evicts full-size decodes.
@MainActor
public final class ThumbnailProvider {
    public let cache: ImageCache
    public let pixelSize: Int
    private var inflight: [URL: Task<CGImage?, Never>] = [:]

    public init(
        pixelSize: Int = 256,
        budgetBytes: Int = 96 * 1024 * 1024
    ) {
        self.pixelSize = pixelSize
        cache = ImageCache(budgetBytes: budgetBytes)
    }

    /// The thumbnail of `url`, or `nil` for files that do not decode.
    public func thumbnail(_ url: URL) async -> CGImage? {
        let key = ImageCache.Key(url: url, maxPixelSize: pixelSize)
        if let hit = await cache.image(for: key) {
            return hit
        }
        if let running = inflight[url] {
            return await running.value
        }
        let size = pixelSize
        let task = Task { () -> CGImage? in
            try? await ImageLoader.downsampled(url, maxPixelSize: size)
        }
        inflight[url] = task
        defer { inflight[url] = nil }
        guard let image = await task.value else {
            return nil
        }
        await cache.insert(image, for: key)
        return image
    }

    public func invalidate(_ url: URL) async {
        await cache.remove(url: url)
    }
}
