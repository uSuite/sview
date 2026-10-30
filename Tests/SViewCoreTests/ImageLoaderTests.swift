import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import SViewCore

struct ImageLoaderTests {
    let temp: TempFolder

    init() throws {
        temp = try TempFolder()
    }

    private func url(_ name: String) -> URL { temp.url.appendingPathComponent(name) }

    @Test func infoReadsSizeTypeAndDepth() throws {
        TestImages.write(url("a.png"), type: .png, width: 40, height: 30)
        let info = try ImageLoader.info(url("a.png"))
        #expect(info.width == 40)
        #expect(info.height == 30)
        #expect(info.frameCount == 1)
        #expect(!info.isAnimated)
        #expect(info.typeIdentifier == "public.png")
        #expect(info.bitDepth == 8)
        #expect(info.orientation == 1)
        #expect(!info.hasGPS)
    }

    @Test func orientationSwapsReportedSizeAndDecode() async throws {
        TestImages.write(
            url("rotated.jpg"),
            type: .jpeg,
            width: 40,
            height: 20,
            properties: [kCGImagePropertyOrientation: 6]
        )
        let info = try ImageLoader.info(url("rotated.jpg"))
        #expect(info.orientation == 6)
        #expect(info.width == 20)
        #expect(info.height == 40)
        let image = try await ImageLoader.full(url("rotated.jpg"))
        #expect(image.width == 20)
        #expect(image.height == 40)
    }

    @Test func exifBasics() throws {
        TestImages.write(
            url("exif.jpg"),
            type: .jpeg,
            width: 8,
            height: 8,
            properties: [
                kCGImagePropertyTIFFDictionary: [
                    kCGImagePropertyTIFFMake: "Fujifilm",
                    kCGImagePropertyTIFFModel: "X-T5",
                ],
                kCGImagePropertyExifDictionary: [
                    kCGImagePropertyExifExposureTime: 0.004,
                    kCGImagePropertyExifFNumber: 2.8,
                    kCGImagePropertyExifISOSpeedRatings: [400],
                    kCGImagePropertyExifLensModel: "XF23mm",
                    kCGImagePropertyExifDateTimeOriginal: "2026:10:25 09:30:00",
                ],
                kCGImagePropertyGPSDictionary: [
                    kCGImagePropertyGPSLatitude: 10.7,
                    kCGImagePropertyGPSLatitudeRef: "N",
                ],
            ]
        )
        let info = try ImageLoader.info(url("exif.jpg"))
        #expect(info.camera == "Fujifilm X-T5")
        #expect(info.lens == "XF23mm")
        #expect(info.exposure == "1/250s f/2.8 ISO 400")
        #expect(info.dateTaken == "2026:10:25 09:30:00")
        #expect(info.hasGPS)
    }

    @Test func downsampledBoundsTheLongEdge() async throws {
        TestImages.write(url("big.png"), type: .png, width: 400, height: 200)
        let image = try await ImageLoader.downsampled(url("big.png"), maxPixelSize: 100)
        #expect(image.width == 100)
        #expect(image.height == 50)
        let small = try await ImageLoader.downsampled(url("big.png"), maxPixelSize: 1000)
        #expect(small.width == 400)
    }

    @Test func fullDecodeRespectsPixelBudget() async throws {
        TestImages.write(url("big.png"), type: .png, width: 400, height: 100)
        let full = try await ImageLoader.full(url("big.png"))
        #expect(full.width == 400)
        let bounded = try await ImageLoader.full(url("big.png"), maxPixels: 10_000)
        #expect(bounded.width * bounded.height <= 10_000)
        #expect(bounded.width == 200)
    }

    @Test func animatedFramesAndDelays() async throws {
        TestImages.write(
            url("anim.gif"),
            type: .gif,
            width: 10,
            height: 10,
            frames: 3,
            frameProperties: [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.25]
            ]
        )
        let info = try ImageLoader.info(url("anim.gif"))
        #expect(info.frameCount == 3)
        #expect(info.isAnimated)
        let delays = try ImageLoader.frameDelays(url("anim.gif"))
        #expect(delays.count == 3)
        #expect(delays.allSatisfy { abs($0 - 0.25) < 0.01 })
        let frame = try await ImageLoader.downsampled(url("anim.gif"), maxPixelSize: 10, frame: 2)
        #expect(frame.width == 10)
        await #expect(throws: ImageLoaderError.decodeFailed(url("anim.gif"))) {
            try await ImageLoader.downsampled(url("anim.gif"), maxPixelSize: 10, frame: 3)
        }
    }

    @Test func stillImageDelayDefault() throws {
        TestImages.write(url("a.png"), type: .png, width: 4, height: 4)
        #expect(try ImageLoader.frameDelays(url("a.png")) == [0.1])
    }

    // MARK: Hostile set (SV-704)

    @Test func zeroByteFileThrows() async throws {
        try temp.file("empty.png", bytes: 0)
        #expect(throws: ImageLoaderError.self) { try ImageLoader.info(url("empty.png")) }
        await #expect(throws: ImageLoaderError.self) {
            try await ImageLoader.downsampled(url("empty.png"), maxPixelSize: 100)
        }
    }

    @Test func textPretendingToBePNGThrows() throws {
        try Data("not an image at all".utf8).write(to: url("fake.png"))
        #expect(throws: ImageLoaderError.self) { try ImageLoader.info(url("fake.png")) }
    }

    @Test func missingFileThrows() async {
        await #expect(throws: ImageLoaderError.self) {
            try await ImageLoader.full(url("missing.png"))
        }
    }

    @Test func truncatedJPEGDoesNotCrash() async throws {
        TestImages.write(url("whole.jpg"), type: .jpeg, width: 200, height: 200)
        let data = try Data(contentsOf: url("whole.jpg"))
        try data.prefix(data.count / 3).write(to: url("truncated.jpg"))
        // ImageIO may return a partial image or fail; either is fine, a crash is not.
        _ = try? await ImageLoader.downsampled(url("truncated.jpg"), maxPixelSize: 100)
        _ = try? await ImageLoader.full(url("truncated.jpg"))
    }

    @Test func headerWithoutSizeThrows() throws {
        TestImages.write(url("whole.jpg"), type: .jpeg, width: 200, height: 200)
        let data = try Data(contentsOf: url("whole.jpg"))
        try data.prefix(40).write(to: url("stub.jpg"))
        #expect(throws: ImageLoaderError.self) { try ImageLoader.info(url("stub.jpg")) }
    }

    @Test func displayReadyDecodesAreNativeBGRAInTheTargetSpace() async throws {
        TestImages.write(url("a.png"), type: .png, width: 40, height: 20)
        let space = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = try await ImageLoader.downsampled(url("a.png"), maxPixelSize: 40, displaySpace: space)
        #expect(image.colorSpace == space)
        #expect(image.bitsPerPixel == 32)
        #expect(image.bitmapInfo.rawValue == CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        #expect(image.width == 40)
        // Already display-ready images come back as they are.
        #expect(ImageLoader.displayReady(image, in: space) === image)
        let full = try await ImageLoader.full(url("a.png"), displaySpace: space)
        #expect(full.colorSpace == space)
    }

    @Test func errorDescriptions() {
        let file = URL(fileURLWithPath: "/x/a.png")
        #expect(ImageLoaderError.unreadable(file).description == "cannot read a.png")
        #expect(ImageLoaderError.notAnImage(file).description.contains("not an image"))
        #expect(ImageLoaderError.decodeFailed(file).description == "a.png could not be decoded")
    }
}
