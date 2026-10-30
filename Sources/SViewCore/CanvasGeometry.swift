import CoreGraphics

/// Zoom and pan arithmetic for the canvas (SV-105, SV-106), kept out of the
/// view so it is unit tested.
///
/// `scale` is device pixels per image pixel: 1 is actual size (1:1 on a
/// Retina screen too), fit is never above 1 so small images are not blown up.
public struct CanvasGeometry: Sendable, Equatable {
    /// Image pixel size after EXIF orientation, before view rotation.
    public var imageSize: CGSize
    /// View size in points.
    public var viewSize: CGSize
    public var backingScale: CGFloat
    public var quarterTurns: Int

    public init(
        imageSize: CGSize,
        viewSize: CGSize,
        backingScale: CGFloat = 2,
        quarterTurns: Int = 0
    ) {
        self.imageSize = imageSize
        self.viewSize = viewSize
        self.backingScale = backingScale
        self.quarterTurns = quarterTurns
    }

    /// Image size in pixels as it appears on screen, rotation applied.
    public var rotatedImageSize: CGSize {
        quarterTurns % 2 == 0 ? imageSize : CGSize(width: imageSize.height, height: imageSize.width)
    }

    private var isEmpty: Bool {
        imageSize.width <= 0 || imageSize.height <= 0 || viewSize.width <= 0 || viewSize.height <= 0
    }

    public func scale(for zoom: ViewState.Zoom) -> Double {
        guard !isEmpty else {
            return 1
        }
        let image = rotatedImageSize
        let widthScale = Double(viewSize.width * backingScale / image.width)
        let heightScale = Double(viewSize.height * backingScale / image.height)
        switch zoom {
        case .fit:
            return min(widthScale, heightScale, 1)
        case .width:
            return widthScale
        case .height:
            return heightScale
        case .actual:
            return 1
        case .scale(let scale):
            return scale
        }
    }

    /// On-screen size of the image in points at `scale`, rotation applied.
    public func displaySize(scale: Double) -> CGSize {
        let image = rotatedImageSize
        let factor = CGFloat(scale) / backingScale
        return CGSize(width: image.width * factor, height: image.height * factor)
    }

    /// Unrotated layer bounds in points at `scale`.
    public func layerSize(scale: Double) -> CGSize {
        let factor = CGFloat(scale) / backingScale
        return CGSize(width: imageSize.width * factor, height: imageSize.height * factor)
    }

    public func overflows(scale: Double) -> (horizontally: Bool, vertically: Bool) {
        let size = displaySize(scale: scale)
        return (size.width > viewSize.width + 0.5, size.height > viewSize.height + 0.5)
    }

    /// Keeps the image covering the view on overflowing axes and centred on
    /// the others. `offset` is the image centre minus the view centre.
    public func clamp(_ offset: CGPoint, scale: Double) -> CGPoint {
        let size = displaySize(scale: scale)
        let limitX = max(0, (size.width - viewSize.width) / 2)
        let limitY = max(0, (size.height - viewSize.height) / 2)
        return CGPoint(
            x: min(max(offset.x, -limitX), limitX),
            y: min(max(offset.y, -limitY), limitY)
        )
    }

    /// The offset that keeps the image point under `anchor` (relative to the
    /// view centre) fixed while the scale goes from `from` to `to`.
    public static func anchoredOffset(
        _ offset: CGPoint,
        anchor: CGPoint,
        from: Double,
        to: Double
    ) -> CGPoint {
        guard from > 0 else {
            return offset
        }
        let ratio = CGFloat(to / from)
        return CGPoint(
            x: anchor.x - (anchor.x - offset.x) * ratio,
            y: anchor.y - (anchor.y - offset.y) * ratio
        )
    }

    /// Long-edge pixels a decode needs to look sharp at `scale`; at most the
    /// image's own long edge.
    public func decodePixelSize(scale: Double) -> Int {
        let long = Double(max(imageSize.width, imageSize.height))
        return Int(min(long, (long * scale).rounded(.up)))
    }

    /// Long-edge pixels for a window-size decode of an image of unknown size:
    /// the view's long edge in device pixels.
    public static func windowPixelSize(
        viewSize: CGSize,
        backingScale: CGFloat
    ) -> Int {
        Int((max(viewSize.width, viewSize.height) * backingScale).rounded(.up))
    }
}
