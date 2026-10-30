import CoreGraphics
import Foundation
import Testing
@testable import SViewCore

struct ImageCacheTests {
    private func key(_ name: String, _ size: Int = 100) -> ImageCache.Key {
        ImageCache.Key(url: URL(fileURLWithPath: "/f/\(name)"), maxPixelSize: size)
    }

    /// 10 x 10 RGBA, 400 bytes (bytesPerRow may pad, so measure it).
    private let image = TestImages.image(width: 10, height: 10)

    @Test func insertAndHit() async {
        let cache = ImageCache(budgetBytes: 1_000_000)
        await cache.insert(image, for: key("a"))
        #expect(await cache.image(for: key("a")) != nil)
        #expect(await cache.image(for: key("b")) == nil)
        #expect(await cache.contains(key("a")))
        #expect(await cache.totalCost == ImageCache.cost(of: image))
    }

    @Test func evictsLeastRecentlyUsed() async {
        let cost = ImageCache.cost(of: image)
        let cache = ImageCache(budgetBytes: cost * 2)
        await cache.insert(image, for: key("a"))
        await cache.insert(image, for: key("b"))
        _ = await cache.image(for: key("a"))
        await cache.insert(image, for: key("c"))
        #expect(await cache.contains(key("a")))
        #expect(await !cache.contains(key("b")))
        #expect(await cache.contains(key("c")))
        #expect(await cache.count == 2)
        #expect(await cache.totalCost <= cost * 2)
    }

    @Test func oversizedImageIsNotCached() async {
        let cache = ImageCache(budgetBytes: 10)
        await cache.insert(image, for: key("a"))
        #expect(await cache.count == 0)
        #expect(await cache.totalCost == 0)
    }

    @Test func reinsertReplacesCost() async {
        let cache = ImageCache(budgetBytes: 1_000_000)
        await cache.insert(image, for: key("a"))
        await cache.insert(image, for: key("a"))
        #expect(await cache.count == 1)
        #expect(await cache.totalCost == ImageCache.cost(of: image))
    }

    @Test func removeByURLAndAll() async {
        let cache = ImageCache(budgetBytes: 1_000_000)
        await cache.insert(image, for: key("a", 100))
        await cache.insert(image, for: key("a", 0))
        await cache.insert(image, for: key("b"))
        await cache.remove(url: URL(fileURLWithPath: "/f/a"))
        #expect(await cache.count == 1)
        await cache.removeAll()
        #expect(await cache.count == 0)
        #expect(await cache.totalCost == 0)
    }

    @Test func shrinkingBudgetEvicts() async {
        let cost = ImageCache.cost(of: image)
        let cache = ImageCache(budgetBytes: cost * 3)
        for name in ["a", "b", "c"] {
            await cache.insert(image, for: key(name))
        }
        await cache.setBudget(cost)
        #expect(await cache.count == 1)
        #expect(await cache.contains(key("c")))
        #expect(await cache.budget == cost)
    }

    @Test func bestPicksSmallestSufficientDecode() async {
        let cache = ImageCache(budgetBytes: 10_000_000)
        let small = TestImages.image(width: 50, height: 25)
        let large = TestImages.image(width: 400, height: 200)
        await cache.insert(small, for: key("a", 50))
        await cache.insert(large, for: key("a", 0))
        #expect(await cache.best(for: URL(fileURLWithPath: "/f/a"), minPixelSize: 40)?.width == 50)
        #expect(await cache.best(for: URL(fileURLWithPath: "/f/a"), minPixelSize: 100)?.width == 400)
        #expect(await cache.best(for: URL(fileURLWithPath: "/f/a"), minPixelSize: 9000)?.width == 400)
        #expect(await cache.best(for: URL(fileURLWithPath: "/f/zzz"), minPixelSize: 1) == nil)
    }
}

struct PreloadPlanTests {
    @Test func alternatesForwardFirst() {
        #expect(PreloadPlan.indices(around: 5, count: 10, radius: 2, wraps: false) == [6, 4, 7, 3])
    }

    @Test func clampsAtEdgesWithoutWrap() {
        #expect(PreloadPlan.indices(around: 0, count: 10, radius: 2, wraps: false) == [1, 2])
        #expect(PreloadPlan.indices(around: 9, count: 10, radius: 2, wraps: false) == [8, 7])
    }

    @Test func wrapsAndDeduplicates() {
        #expect(PreloadPlan.indices(around: 0, count: 10, radius: 2, wraps: true) == [1, 9, 2, 8])
        #expect(PreloadPlan.indices(around: 0, count: 3, radius: 5, wraps: true) == [1, 2])
    }

    @Test func degenerateInputs() {
        #expect(PreloadPlan.indices(around: 0, count: 1, radius: 2, wraps: true).isEmpty)
        #expect(PreloadPlan.indices(around: 3, count: 10, radius: 0, wraps: false).isEmpty)
        #expect(PreloadPlan.indices(around: 12, count: 10, radius: 2, wraps: false).isEmpty)
    }
}
