import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SViewCore

@MainActor
struct ImagePipelineTests {
    let temp: TempFolder
    let pipeline = ImagePipeline(budgetBytes: 64 * 1024 * 1024)

    init() throws {
        temp = try TempFolder()
        for name in ["a", "b", "c"] {
            TestImages.write(temp.url.appendingPathComponent("\(name).png"), type: .png, width: 1200, height: 600)
        }
    }

    private func url(_ name: String) -> URL { temp.url.appendingPathComponent(name) }

    @Test func bucketsRoundUp() {
        #expect(ImagePipeline.bucket(1) == 256)
        #expect(ImagePipeline.bucket(256) == 256)
        #expect(ImagePipeline.bucket(257) == 512)
    }

    @Test func keyNormalisesToFullAtTheLongEdge() throws {
        let info = try ImageLoader.info(url("a.png"))
        #expect(ImagePipeline.key(for: url("a.png"), maxPixelSize: 300, info: info).maxPixelSize == 512)
        #expect(ImagePipeline.key(for: url("a.png"), maxPixelSize: 1100, info: info).maxPixelSize == 0)
        #expect(ImagePipeline.key(for: url("a.png"), maxPixelSize: 0, info: info).maxPixelSize == 0)
    }

    @Test func decodesOnceThenHitsTheCache() async throws {
        let first = try await pipeline.image(url("a.png"), maxPixelSize: 300)
        #expect(first.width == 512)
        let again = try await pipeline.image(url("a.png"), maxPixelSize: 400)
        #expect(again.width == 512)
        #expect(pipeline.decodeCount == 1)
        let full = try await pipeline.image(url("a.png"), maxPixelSize: 0)
        #expect(full.width == 1200)
        #expect(pipeline.decodeCount == 2)
    }

    @Test func concurrentRequestsShareOneDecode() async throws {
        async let one = pipeline.image(url("b.png"), maxPixelSize: 600)
        async let two = pipeline.image(url("b.png"), maxPixelSize: 600)
        let images = try await [one, two]
        #expect(images.count == 2)
        #expect(pipeline.decodeCount == 1)
    }

    @Test func cachedReturnsBestAvailable() async throws {
        #expect(await pipeline.cached(url("a.png"), minPixelSize: 100) == nil)
        _ = try await pipeline.image(url("a.png"), maxPixelSize: 0)
        #expect(await pipeline.cached(url("a.png"), minPixelSize: 100)?.width == 1200)
    }

    @Test func preloadFillsTheCacheInOrder() async throws {
        pipeline.preload([url("b.png"), url("c.png")], maxPixelSize: 256)
        await pipeline.waitForPreload()
        #expect(pipeline.decodeCount == 2)
        _ = try await pipeline.image(url("c.png"), maxPixelSize: 256)
        #expect(pipeline.decodeCount == 2)
    }

    @Test func invalidateForgetsInfoAndDecodes() async throws {
        _ = try await pipeline.image(url("a.png"), maxPixelSize: 256)
        TestImages.write(url("a.png"), type: .png, width: 100, height: 100)
        #expect(try await pipeline.info(url("a.png")).width == 1200)
        await pipeline.invalidate(url("a.png"))
        #expect(try await pipeline.info(url("a.png")).width == 100)
        #expect(await pipeline.cache.count == 0)
        await pipeline.setBudget(1)
        #expect(await pipeline.cache.budget == 1)
    }

    @Test func errorsPropagate() async throws {
        try temp.file("empty.png", bytes: 0)
        await #expect(throws: ImageLoaderError.self) {
            try await pipeline.image(url("empty.png"), maxPixelSize: 256)
        }
        pipeline.preload([url("empty.png"), url("a.png")], maxPixelSize: 256)
        await pipeline.waitForPreload()
        #expect(pipeline.decodeCount == 1)
    }
}
