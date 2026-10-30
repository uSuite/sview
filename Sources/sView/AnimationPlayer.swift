import AppKit
import ImageIO
import SViewCore

/// Plays an animated GIF, APNG or WebP on the canvas (SV-108). ImageIO's
/// animation API does the timing and decoding; pausing stops it and resuming
/// restarts it at the next frame. Frame step decodes one frame directly.
@MainActor
final class AnimationPlayer {
    /// Receives each frame to show.
    var onFrame: (CGImage) -> Void = { _ in }

    private(set) var state: AnimationState?
    private var url: URL?
    /// Bumped on every start and stop; a running animation whose generation
    /// is stale stops itself on its next frame.
    private var generation = 0

    var isActive: Bool { state != nil }

    func start(_ url: URL, frameCount: Int) {
        stop()
        self.url = url
        state = AnimationState(frameCount: frameCount)
        run(from: 0)
    }

    func stop() {
        generation += 1
        state = nil
        url = nil
    }

    /// Returns a toast describing the new state, `nil` when nothing animates.
    func togglePlaying() -> String? {
        guard var current = state else {
            return nil
        }
        current.togglePlaying()
        state = current
        if current.isPlaying {
            run(from: current.resumeIndex)
            return "playing"
        }
        generation += 1
        return "paused at \(current.label)"
    }

    func step(_ count: Int) -> String? {
        guard var current = state, let url else {
            return nil
        }
        generation += 1
        current.step(count)
        state = current
        let frame = current.index
        let expected = generation
        Task { @MainActor in
            guard let image = try? await ImageLoader.downsampled(url, maxPixelSize: 16_384, frame: frame),
                expected == generation
            else {
                return
            }
            onFrame(image)
        }
        return current.label
    }

    private func run(from start: Int) {
        guard let url else {
            return
        }
        generation += 1
        let expected = generation
        let options = [kCGImageAnimationStartIndex: start] as CFDictionary
        CGAnimateImageAtURLWithBlock(url as CFURL, options) { [weak self] index, image, stop in
            MainActor.assumeIsolated {
                guard let self, self.generation == expected, self.state?.isPlaying == true else {
                    stop.pointee = true
                    return
                }
                self.state?.show(index)
                self.onFrame(image)
            }
        }
    }
}
