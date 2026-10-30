// Writes benchmark images into the folder given as the first argument:
// launch/large.jpg, a ~4 MB 4032x3024 JPEG (SV-102), and browse/, a folder
// of 1920x1280 photos-like JPEGs. Noise keeps the files photo-sized.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let browseCount = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 100 : 100
var seed: UInt64 = 42

func random() -> UInt8 {
    seed = seed &* 6364136223846793005 &+ 1442695040888963407
    return UInt8(truncatingIfNeeded: seed >> 56)
}

func noisy(width: Int, height: Int, tint: Int) -> CGImage {
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let n = Int(random() / 3)
            pixels[i] = UInt8(min(255, (x * 255 / width + tint + n) % 256))
            pixels[i + 1] = UInt8(min(255, (y * 255 / height + n) % 256))
            pixels[i + 2] = UInt8((tint * 3 + n) % 256)
            pixels[i + 3] = 255
        }
    }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    return CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

func write(_ image: CGImage, to path: String, quality: Double) {
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
}

write(noisy(width: 4032, height: 3024, tint: 40), to: "launch/large.jpg", quality: 0.5)
for n in 1...browseCount {
    write(noisy(width: 1920, height: 1280, tint: n * 7), to: String(format: "browse/img-%03d.jpg", n), quality: 0.6)
}
print("bench images written to \(root.path)")
