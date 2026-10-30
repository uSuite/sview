import CoreGraphics
import Foundation

/// The loading path the canvas uses (SV-103, SV-104): header info, decodes
/// at a requested size through the cache, one in-flight decode per key, and
/// nearest-first preloading of neighbours.
@MainActor
public final class ImagePipeline {
    public let cache: ImageCache
    /// When set, decodes come back ready for this display colour space so
    /// Core Animation does not convert them on the main thread.
    public var displaySpace: CGColorSpace?
    /// Decodes that actually ran, for tests and the bench.
    public private(set) var decodeCount = 0

    private var infos: [URL: ImageInfo] = [:]
    private var inflight: [ImageCache.Key: Task<CGImage, any Error>] = [:]
    private var preloadTask: Task<Void, Never>?
    private static let infoLimit = 4096
    /// Window-size decodes are rounded up to this step so small resizes reuse them.
    public static let bucketStep = 256

    public init(budgetBytes: Int) {
        cache = ImageCache(budgetBytes: budgetBytes)
    }

    public func info(_ url: URL) async throws -> ImageInfo {
        if let known = infos[url] {
            return known
        }
        let info = try await Self.readInfo(url)
        if infos.count >= Self.infoLimit {
            infos.removeAll()
        }
        infos[url] = info
        return info
    }

    @concurrent
    private static func readInfo(_ url: URL) async throws -> ImageInfo {
        try ImageLoader.info(url)
    }

    public static func bucket(_ size: Int) -> Int {
        max(bucketStep, ((size + bucketStep - 1) / bucketStep) * bucketStep)
    }

    /// Requests at or past the image's long edge share the full-resolution key.
    public static func key(
        for url: URL,
        maxPixelSize: Int,
        info: ImageInfo
    ) -> ImageCache.Key {
        let long = max(info.width, info.height)
        let size = maxPixelSize <= 0 ? 0 : bucket(maxPixelSize)
        return ImageCache.Key(
            url: url,
            maxPixelSize: size == 0 || size >= long ? 0 : size
        )
    }

    /// A decode no smaller than `maxPixelSize` on the long edge (0 for full
    /// resolution), from the cache when possible.
    public func image(
        _ url: URL,
        maxPixelSize: Int
    ) async throws -> CGImage {
        let info = try await info(url)
        let key = Self.key(for: url, maxPixelSize: maxPixelSize, info: info)
        if let hit = await cache.image(for: key) {
            return hit
        }
        if let running = inflight[key] {
            return try await running.value
        }
        let space = displaySpace
        let task = Task { () throws -> CGImage in
            if key.maxPixelSize == 0 {
                return try await ImageLoader.full(url, displaySpace: space)
            }
            return try await ImageLoader.downsampled(url, maxPixelSize: key.maxPixelSize, displaySpace: space)
        }
        inflight[key] = task
        defer { inflight[key] = nil }
        let image = try await task.value
        decodeCount += 1
        await cache.insert(image, for: key)
        return image
    }

    /// Any cached decode of `url` at least `minPixelSize` on the long edge,
    /// to show at once while a better one loads.
    public func cached(
        _ url: URL,
        minPixelSize: Int
    ) async -> CGImage? {
        await cache.best(for: url, minPixelSize: minPixelSize)
    }

    /// Replaces the preload queue: decodes `urls` in order, one at a time,
    /// until done or replaced by the next call.
    public func preload(
        _ urls: [URL],
        maxPixelSize: Int
    ) {
        preloadTask?.cancel()
        preloadTask = Task { [weak self] in
            for url in urls {
                guard !Task.isCancelled, let self else {
                    return
                }
                _ = try? await self.image(url, maxPixelSize: maxPixelSize)
            }
        }
    }

    /// Waits for the current preload queue, for tests and the bench.
    public func waitForPreload() async {
        await preloadTask?.value
    }

    /// Forgets `url` after it changed or vanished on disk.
    public func invalidate(_ url: URL) async {
        infos[url] = nil
        await cache.remove(url: url)
    }

    public func setBudget(_ bytes: Int) async {
        await cache.setBudget(bytes)
    }
}
