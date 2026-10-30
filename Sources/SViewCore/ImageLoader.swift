import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageLoaderError: Error, Equatable, CustomStringConvertible {
    case unreadable(URL)
    case notAnImage(URL)
    case decodeFailed(URL)

    public var description: String {
        switch self {
        case .unreadable(let url):
            return "cannot read \(url.lastPathComponent)"
        case .notAnImage(let url):
            return "\(url.lastPathComponent) is not an image ImageIO can decode"
        case .decodeFailed(let url):
            return "\(url.lastPathComponent) could not be decoded"
        }
    }
}

/// What the info overlay and title need, read without decoding pixels (SV-401).
public struct ImageInfo: Sendable, Equatable {
    /// Pixel size after EXIF orientation is applied.
    public var width: Int
    public var height: Int
    public var frameCount: Int
    public var typeIdentifier: String?
    /// EXIF orientation 1 to 8.
    public var orientation: Int
    public var colorModel: String?
    public var profileName: String?
    public var bitDepth: Int?
    public var hasAlpha: Bool
    public var camera: String?
    public var lens: String?
    public var exposure: String?
    public var dateTaken: String?
    public var hasGPS: Bool

    public var isAnimated: Bool { frameCount > 1 }
}

/// ImageIO decoding off the main thread (SV-103, SV-107, SV-109).
///
/// Every decode applies the EXIF orientation, so callers never rotate.
/// Corrupt, empty or non-image files throw; they never crash.
public enum ImageLoader {
    /// Full decodes above this many pixels are scaled down to fit it, so a
    /// hostile 20k x 20k file cannot take gigabytes (SV-704).
    public static let defaultMaxFullPixels = 16_384 * 16_384

    static func source(_ url: URL) throws(ImageLoaderError) -> CGImageSource {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            throw .unreadable(url)
        }
        guard CGImageSourceGetCount(source) > 0, CGImageSourceGetType(source) != nil else {
            throw .notAnImage(url)
        }
        return source
    }

    public static func info(_ url: URL) throws(ImageLoaderError) -> ImageInfo {
        let source = try source(url)
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw .notAnImage(url)
        }
        let rawWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let rawHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        // A truncated header can name a type but no size; nothing to show.
        guard rawWidth > 0, rawHeight > 0 else {
            throw .notAnImage(url)
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let sideways = (5...8).contains(orientation)
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let camera = [tiff[kCGImagePropertyTIFFMake], tiff[kCGImagePropertyTIFFModel]]
            .compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return ImageInfo(
            width: sideways ? rawHeight : rawWidth,
            height: sideways ? rawWidth : rawHeight,
            frameCount: CGImageSourceGetCount(source),
            typeIdentifier: CGImageSourceGetType(source) as String?,
            orientation: orientation,
            colorModel: properties[kCGImagePropertyColorModel] as? String,
            profileName: properties[kCGImagePropertyProfileName] as? String,
            bitDepth: properties[kCGImagePropertyDepth] as? Int,
            hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
            camera: camera.isEmpty ? nil : camera,
            lens: exif[kCGImagePropertyExifLensModel] as? String,
            exposure: exposure(exif),
            dateTaken: exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            hasGPS: properties[kCGImagePropertyGPSDictionary] != nil
        )
    }

    private static func exposure(_ exif: [CFString: Any]) -> String? {
        var parts: [String] = []
        if let time = exif[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            parts.append(time < 1 ? "1/\(Int((1 / time).rounded()))s" : "\(time)s")
        }
        if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double {
            parts.append(String(format: "f/%.1f", fNumber))
        }
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first {
            parts.append("ISO \(iso)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Decode no larger than `maxPixelSize` on the long edge, for display at
    /// window size. Small images come back at their own size.
    @concurrent
    public static func downsampled(
        _ url: URL,
        maxPixelSize: Int,
        frame: Int = 0,
        displaySpace: CGColorSpace? = nil
    ) async throws(ImageLoaderError) -> CGImage {
        let image = try decode(url, maxPixelSize: max(1, maxPixelSize), frame: frame)
        return displaySpace.flatMap { displayReady(image, in: $0) } ?? image
    }

    /// Full-resolution decode, used past 1:1 zoom; bounded by `maxPixels`.
    @concurrent
    public static func full(
        _ url: URL,
        frame: Int = 0,
        maxPixels: Int = defaultMaxFullPixels,
        displaySpace: CGColorSpace? = nil
    ) async throws(ImageLoaderError) -> CGImage {
        let image = try fullDecode(url, frame: frame, maxPixels: maxPixels)
        return displaySpace.flatMap { displayReady(image, in: $0) } ?? image
    }

    static func fullDecode(
        _ url: URL,
        frame: Int,
        maxPixels: Int
    ) throws(ImageLoaderError) -> CGImage {
        let info = try info(url)
        let long = max(info.width, info.height)
        let pixels = info.width * info.height
        guard pixels > maxPixels else {
            return try decode(url, maxPixelSize: max(1, long), frame: frame)
        }
        let scale = (Double(maxPixels) / Double(pixels)).squareRoot()
        return try decode(url, maxPixelSize: max(1, Int(Double(long) * scale)), frame: frame)
    }

    static func decode(
        _ url: URL,
        maxPixelSize: Int,
        frame: Int
    ) throws(ImageLoaderError) -> CGImage {
        let source = try source(url)
        guard frame >= 0, frame < CGImageSourceGetCount(source) else {
            throw .decodeFailed(url)
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, frame, options) else {
            throw .decodeFailed(url)
        }
        return image
    }

    /// `image` redrawn as premultiplied BGRA in `space`, the layout and
    /// colour space Core Animation shows without converting. Done on the
    /// decoding thread so the main thread never colour-matches at commit
    /// (found with Instruments, SV-705). `nil` if the bitmap cannot be made.
    public static func displayReady(_ image: CGImage, in space: CGColorSpace) -> CGImage? {
        let native = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        if image.colorSpace == space, image.bitsPerPixel == 32, image.bitmapInfo.rawValue == native {
            return image
        }
        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: space,
            bitmapInfo: native
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Per-frame delays in seconds for animated images (SV-108). ImageIO
    /// treats delays under 10 ms as 100 ms, as browsers do.
    public static func frameDelays(_ url: URL) throws(ImageLoaderError) -> [Double] {
        let source = try source(url)
        return (0..<CGImageSourceGetCount(source)).map { index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let containers: [(CFString, CFString, CFString)] = [
                (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
                (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
                (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            ]
            for (dictionary, unclamped, clamped) in containers {
                guard let values = properties[dictionary] as? [CFString: Any] else {
                    continue
                }
                let delay = values[unclamped] as? Double ?? values[clamped] as? Double ?? 0.1
                return delay < 0.011 ? 0.1 : delay
            }
            return 0.1
        }
    }
}
