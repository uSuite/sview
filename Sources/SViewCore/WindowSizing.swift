import CoreGraphics

/// Window sizing for `size_window_to_image` (SV-507): the content size that
/// shows an image at 1:1, scaled down to fit the available screen area with
/// its aspect kept, never below the window minimum.
public enum WindowSizing {
    public static func contentSize(
        imagePixels: CGSize,
        backingScale: CGFloat,
        chrome: CGSize = .zero,
        available: CGSize,
        minimum: CGSize
    ) -> CGSize {
        guard imagePixels.width > 0, imagePixels.height > 0, backingScale > 0 else {
            return minimum
        }
        let natural = CGSize(width: imagePixels.width / backingScale, height: imagePixels.height / backingScale)
        let room = CGSize(width: available.width - chrome.width, height: available.height - chrome.height)
        let shrink = min(1, room.width / natural.width, room.height / natural.height)
        let image = CGSize(width: (natural.width * shrink).rounded(), height: (natural.height * shrink).rounded())
        return CGSize(
            width: max(minimum.width, image.width + chrome.width),
            height: max(minimum.height, image.height + chrome.height)
        )
    }

    /// `size` placed with its centre where `frame`'s centre is, moved back
    /// inside `bounds` when it spills over.
    public static func centred(
        _ size: CGSize,
        on frame: CGRect,
        within bounds: CGRect
    ) -> CGRect {
        var rect = CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        rect.origin.x = min(max(rect.minX, bounds.minX), max(bounds.minX, bounds.maxX - rect.width))
        rect.origin.y = min(max(rect.minY, bounds.minY), max(bounds.minY, bounds.maxY - rect.height))
        return rect
    }
}
