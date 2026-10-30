// Generates the sample images under fixtures/ that `make run` and the smoke
// test open. Run with `make fixtures`; output is deterministic and committed.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "fixtures")
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
        green: CGFloat((hex >> 8) & 0xff) / 255,
        blue: CGFloat(hex & 0xff) / 255,
        alpha: alpha
    )
}

func draw(
    width: Int,
    height: Int,
    background: UInt32?,
    label: String,
    accent: UInt32 = 0xf2b134
) -> CGImage {
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
    if let background {
        context.setFillColor(color(background))
        context.fill(bounds)
    }
    // A frame and an arrow pointing up make orientation and edges visible.
    let inset = CGFloat(min(width, height)) * 0.04
    context.setStrokeColor(color(accent))
    context.setLineWidth(max(2, inset / 2))
    context.stroke(bounds.insetBy(dx: inset, dy: inset))
    let cx = CGFloat(width) / 2
    let top = CGFloat(height) - inset * 3
    context.setFillColor(color(accent))
    context.move(to: CGPoint(x: cx, y: top))
    context.addLine(to: CGPoint(x: cx - inset * 2, y: top - inset * 2.5))
    context.addLine(to: CGPoint(x: cx + inset * 2, y: top - inset * 2.5))
    context.closePath()
    context.fillPath()

    let font = CTFontCreateWithName("Menlo-Bold" as CFString, CGFloat(min(width, height)) * 0.12, nil)
    let text = NSAttributedString(
        string: label,
        attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0xffffff),
        ]
    )
    let line = CTLineCreateWithAttributedString(text)
    let lineBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: (CGFloat(width) - lineBounds.width) / 2 - lineBounds.minX,
        y: (CGFloat(height) - lineBounds.height) / 2 - lineBounds.minY
    )
    CTLineDraw(line, context)
    return context.makeImage()!
}

func write(
    _ path: String,
    _ images: [CGImage],
    type: UTType,
    properties: [CFString: Any] = [:],
    frameProperties: [CFString: Any] = [:]
) {
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil)!
    CGImageDestinationSetProperties(destination, properties as CFDictionary)
    for image in images {
        var merged = frameProperties
        merged[kCGImageDestinationLossyCompressionQuality] = 0.7
        CGImageDestinationAddImage(destination, image, merged as CFDictionary)
    }
    precondition(CGImageDestinationFinalize(destination), "cannot write \(path)")
}

func text(_ path: String, _ body: String) {
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! Data(body.utf8).write(to: url)
}

// sample/: one folder covering the viewer cases.
write("sample/photo-01.jpg", [draw(width: 1600, height: 1000, background: 0x2d5f8a, label: "01 landscape")], type: .jpeg)
write("sample/photo-02.jpg", [draw(width: 900, height: 1400, background: 0x6a3d7c, label: "02 portrait")], type: .jpeg)
write("sample/photo-03.png", [draw(width: 800, height: 800, background: nil, label: "03 alpha")], type: .png)
/// `image` turned a quarter counter-clockwise, as a camera held upright
/// stores a portrait shot that EXIF orientation 6 turns back.
func rotatedCounterClockwise(_ image: CGImage) -> CGImage {
    let context = CGContext(
        data: nil,
        width: image.height,
        height: image.width,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: sRGB,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.translateBy(x: CGFloat(image.height), y: 0)
    context.rotate(by: .pi / 2)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()!
}

// Stored landscape with EXIF orientation 6: must display as portrait, arrow up.
write(
    "sample/photo-04.jpg",
    [rotatedCounterClockwise(draw(width: 800, height: 1200, background: 0x8a5a2d, label: "04 exif"))],
    type: .jpeg,
    frameProperties: [kCGImagePropertyOrientation: 6]
)
write("sample/photo-10.png", [draw(width: 1000, height: 700, background: 0x2d8a5a, label: "10 natural")], type: .png)
write("sample/tiny.png", [draw(width: 64, height: 48, background: 0x8a2d2d, label: "t")], type: .png)
write("sample/wide.jpg", [draw(width: 6000, height: 800, background: 0x3d3d3d, label: "wide panorama, pan with h and l")], type: .jpeg)
write(
    "sample/anim.gif",
    (1...4).map { draw(width: 400, height: 300, background: [0xaa3333, 0x33aa33, 0x3333aa, 0xaaaa33][$0 - 1], label: "frame \($0)") },
    type: .gif,
    properties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]],
    frameProperties: [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.4]]
)
// A truncated JPEG: shows the in-viewport error, never a modal.
let whole = root.appendingPathComponent("sample/photo-01.jpg")
try! Data(contentsOf: whole).prefix(600).write(to: root.appendingPathComponent("sample/broken.jpg"))
text("sample/notes.txt", "Not an image; sView skips it.\n")
text("sample/.hidden.png", "hidden files are skipped\n")

// poc/: a PoC evidence tree for ] [ and the case title.
let product = "poc/poc-demo"
for (action, count) in [("vm-start", 3), ("vm-stop", 2)] {
    for n in 1...count {
        let id = "poc-demo-\(action)"
        write(
            "\(product)/\(id)/\(id)-\(String(format: "%02d", n)).png",
            [draw(width: 1280, height: 800, background: 0x1e2a38, label: "\(action) \(n)")],
            type: .png
        )
    }
}
text("\(product)/poc-demo-vm-empty/poc-demo-vm-empty.md", "# poc-demo-vm-empty\n\nNo captures yet.\n")
write(
    "\(product)/poc-demo-vm-tag/scap-2026-10-25-101500.png",
    [draw(width: 1280, height: 800, background: 0x1e2a38, label: "vm-tag scap")],
    type: .png
)
text(
    "\(product)/poc-demo-vm-start/poc-demo-vm-start.md",
    """
    # poc-demo-vm-start

    - Open the VM list and pick a stopped VM

    ![poc-demo-vm-start-01](poc-demo-vm-start-01.png)

    - Press Start and confirm in the dialog

    ![poc-demo-vm-start-02](poc-demo-vm-start-02.png)

    - The VM shows Running within a minute

    ![poc-demo-vm-start-03](poc-demo-vm-start-03.png)

    """
)
print("fixtures written to \(root.path)")
