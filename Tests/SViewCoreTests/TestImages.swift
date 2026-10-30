import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writes small images with ImageIO so tests need no binary fixtures.
enum TestImages {
    static func image(
        width: Int,
        height: Int,
        alpha: Bool = false
    ) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: alpha ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    @discardableResult
    static func write(
        _ url: URL,
        type: UTType,
        width: Int,
        height: Int,
        properties: [CFString: Any] = [:],
        frames: Int = 1,
        frameProperties: [CFString: Any] = [:]
    ) -> URL {
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            frames,
            nil
        )!
        for _ in 0..<frames {
            var merged = properties
            merged.merge(frameProperties) { $1 }
            CGImageDestinationAddImage(
                destination,
                image(width: width, height: height),
                merged as CFDictionary
            )
        }
        precondition(CGImageDestinationFinalize(destination))
        return url
    }
}
