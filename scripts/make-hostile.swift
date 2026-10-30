// Writes the hostile fixture set (SV-704) into the folder given as the first
// argument. Generated, not committed: the 20k x 20k PNG alone is large.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
try? fm.removeItem(at: root)
try! fm.createDirectory(at: root.appendingPathComponent("files"), withIntermediateDirectories: true)

func path(_ name: String) -> URL { root.appendingPathComponent(name) }

func small(_ shade: UInt8, size: Int = 64) -> CGImage {
    let pixels = [UInt8](repeating: shade, count: size * size)
    return CGImage(
        width: size,
        height: size,
        bitsPerComponent: 8,
        bitsPerPixel: 8,
        bytesPerRow: size,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGBitmapInfo(rawValue: 0),
        provider: CGDataProvider(data: Data(pixels) as CFData)!,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent
    )!
}

func write(_ images: [CGImage], to url: URL, type: UTType, frame: [CFString: Any] = [:]) {
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil)!
    for image in images {
        CGImageDestinationAddImage(destination, image, frame as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(destination))
}

// Empty, truncated and fake files.
fm.createFile(atPath: path("files/zero-byte.png").path, contents: Data())
write([small(200, size: 800)], to: path("files/whole.jpg"), type: .jpeg)
let jpeg = try! Data(contentsOf: path("files/whole.jpg"))
try! jpeg.prefix(jpeg.count / 4).write(to: path("files/truncated.jpg"))
try! fm.removeItem(at: path("files/whole.jpg"))
try! Data("plain text pretending to be a PNG\n".utf8).write(to: path("files/fake.png"))

// 500-frame GIF.
write(
    (0..<500).map { small(UInt8($0 % 256)) },
    to: path("files/frames-500.gif"),
    type: .gif,
    frame: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.02]]
)

// 20000 x 20000 gray PNG, rows produced on demand so writing it stays small.
let side = 20_000
final class Rows {
    var offset = 0
}
let rows = Rows()
var callbacks = CGDataProviderSequentialCallbacks(
    version: 0,
    getBytes: { info, buffer, count in
        let state = Unmanaged<Rows>.fromOpaque(info!).takeUnretainedValue()
        let bytes = buffer.assumingMemoryBound(to: UInt8.self)
        for index in 0..<count {
            bytes[index] = UInt8(truncatingIfNeeded: ((state.offset + index) / 20_000) / 80)
        }
        state.offset += count
        return count
    },
    skipForward: { info, count in
        let state = Unmanaged<Rows>.fromOpaque(info!).takeUnretainedValue()
        state.offset += Int(count)
        return count
    },
    rewind: { info in
        Unmanaged<Rows>.fromOpaque(info!).takeUnretainedValue().offset = 0
    },
    releaseInfo: nil
)
let provider = CGDataProvider(sequentialInfo: Unmanaged.passUnretained(rows).toOpaque(), callbacks: &callbacks)!
let huge = CGImage(
    width: side,
    height: side,
    bitsPerComponent: 8,
    bitsPerPixel: 8,
    bytesPerRow: side,
    space: CGColorSpaceCreateDeviceGray(),
    bitmapInfo: CGBitmapInfo(rawValue: 0),
    provider: provider,
    decode: nil,
    shouldInterpolate: false,
    intent: .defaultIntent
)!
write([huge], to: path("files/huge-20k.png"), type: .png)

// 10,000-file folder of hard links to one small PNG.
let many = path("many")
try! fm.createDirectory(at: many, withIntermediateDirectories: true)
write([small(90)], to: many.appendingPathComponent("img-00000.png"), type: .png)
for n in 1..<10_000 {
    try! fm.linkItem(
        at: many.appendingPathComponent("img-00000.png"),
        to: many.appendingPathComponent(String(format: "img-%05d.png", n))
    )
}
print("hostile set written to \(root.path)")
