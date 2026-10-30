import CoreGraphics
import Testing
@testable import SViewCore

struct WindowSizingTests {
    private let screen = CGSize(width: 1600, height: 1000)
    private let minimum = CGSize(width: 320, height: 240)

    @Test func smallImagesShowAtOneToOne() {
        let size = WindowSizing.contentSize(
            imagePixels: CGSize(width: 1200, height: 800),
            backingScale: 2,
            available: screen,
            minimum: minimum
        )
        #expect(size == CGSize(width: 600, height: 400))
    }

    @Test func largeImagesShrinkKeepingAspect() {
        let size = WindowSizing.contentSize(
            imagePixels: CGSize(width: 6000, height: 1000),
            backingScale: 1,
            available: screen,
            minimum: minimum
        )
        #expect(size == CGSize(width: 1600, height: 267))
    }

    @Test func chromeIsAddedAndMinimumHolds() {
        let size = WindowSizing.contentSize(
            imagePixels: CGSize(width: 64, height: 48),
            backingScale: 2,
            chrome: CGSize(width: 260, height: 96),
            available: screen,
            minimum: minimum
        )
        #expect(size == CGSize(width: 320, height: 240))
        #expect(WindowSizing.contentSize(imagePixels: .zero, backingScale: 2, available: screen, minimum: minimum) == minimum)
    }

    @Test func centredStaysOnScreen() {
        let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1000)
        let frame = CGRect(x: 1300, y: 800, width: 200, height: 100)
        let rect = WindowSizing.centred(CGSize(width: 600, height: 400), on: frame, within: bounds)
        #expect(rect == CGRect(x: 1000, y: 600, width: 600, height: 400))
        let centre = WindowSizing.centred(CGSize(width: 400, height: 200), on: CGRect(x: 600, y: 400, width: 400, height: 200), within: bounds)
        #expect(centre == CGRect(x: 600, y: 400, width: 400, height: 200))
    }
}
