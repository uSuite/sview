import CoreGraphics
import Testing
@testable import SViewCore

struct CanvasGeometryTests {
    private let big = CanvasGeometry(
        imageSize: CGSize(width: 4000, height: 2000),
        viewSize: CGSize(width: 1000, height: 800),
        backingScale: 2
    )

    @Test func fitShrinksButNeverEnlarges() {
        #expect(big.scale(for: .fit) == 0.5)
        let small = CanvasGeometry(
            imageSize: CGSize(width: 64, height: 48),
            viewSize: CGSize(width: 1000, height: 800)
        )
        #expect(small.scale(for: .fit) == 1)
    }

    @Test func modes() {
        #expect(big.scale(for: .width) == 0.5)
        #expect(big.scale(for: .height) == 0.8)
        #expect(big.scale(for: .actual) == 1)
        #expect(big.scale(for: .scale(3)) == 3)
    }

    @Test func rotationSwapsTheFittedAxis() {
        var rotated = big
        rotated.quarterTurns = 1
        #expect(rotated.rotatedImageSize == CGSize(width: 2000, height: 4000))
        #expect(rotated.scale(for: .fit) == 0.4)
        #expect(rotated.displaySize(scale: 0.4) == CGSize(width: 400, height: 800))
        #expect(rotated.layerSize(scale: 0.4) == CGSize(width: 800, height: 400))
    }

    @Test func displaySizeIsInPoints() {
        #expect(big.displaySize(scale: 1) == CGSize(width: 2000, height: 1000))
        var oneX = big
        oneX.backingScale = 1
        #expect(oneX.displaySize(scale: 1) == CGSize(width: 4000, height: 2000))
    }

    @Test func overflowAndClamp() {
        let fit = big.scale(for: .fit)
        #expect(big.overflows(scale: fit) == (false, false))
        #expect(big.overflows(scale: 1) == (true, true))
        #expect(big.overflows(scale: 0.6) == (true, false))
        #expect(big.clamp(CGPoint(x: 5000, y: -5000), scale: 1) == CGPoint(x: 500, y: -100))
        #expect(big.clamp(CGPoint(x: 300, y: 300), scale: fit) == .zero)
    }

    @Test func anchoredZoomKeepsThePointUnderTheCursor() {
        let offset = CanvasGeometry.anchoredOffset(
            CGPoint(x: 0, y: 0),
            anchor: CGPoint(x: 100, y: 50),
            from: 1,
            to: 2
        )
        #expect(offset == CGPoint(x: -100, y: -50))
        // Zooming about the centre scales the offset.
        #expect(
            CanvasGeometry.anchoredOffset(CGPoint(x: 40, y: 10), anchor: .zero, from: 1, to: 0.5)
                == CGPoint(x: 20, y: 5)
        )
        #expect(CanvasGeometry.anchoredOffset(CGPoint(x: 1, y: 1), anchor: .zero, from: 0, to: 2) == CGPoint(x: 1, y: 1))
    }

    @Test func decodeSizes() {
        #expect(big.decodePixelSize(scale: 0.5) == 2000)
        #expect(big.decodePixelSize(scale: 3) == 4000)
        #expect(CanvasGeometry.windowPixelSize(viewSize: CGSize(width: 1000, height: 800), backingScale: 2) == 2000)
    }

    @Test func emptyInputsAreSafe() {
        let empty = CanvasGeometry(imageSize: .zero, viewSize: CGSize(width: 100, height: 100))
        #expect(empty.scale(for: .fit) == 1)
        #expect(empty.displaySize(scale: 1) == .zero)
    }
}
