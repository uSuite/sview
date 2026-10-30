import Foundation
import Testing
import UniformTypeIdentifiers
@testable import SViewCore

@MainActor
struct ThumbnailProviderTests {
    @Test func thumbnailsAreSmallCachedAndNilOnError() async throws {
        let temp = try TempFolder()
        let url = TestImages.write(temp.url.appendingPathComponent("a.png"), type: .png, width: 1600, height: 800)
        let provider = ThumbnailProvider(pixelSize: 128)
        let first = try #require(await provider.thumbnail(url))
        #expect(first.width == 128)
        #expect(first.height == 64)
        #expect(await provider.cache.count == 1)
        #expect(await provider.thumbnail(url) === first)
        await provider.invalidate(url)
        #expect(await provider.cache.count == 0)
        try temp.file("bad.png", bytes: 0)
        #expect(await provider.thumbnail(temp.url.appendingPathComponent("bad.png")) == nil)
    }
}
