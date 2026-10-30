/// Frame position of an animated image (SV-108): playing or paused, and
/// stepping that wraps in both directions.
public struct AnimationState: Sendable, Equatable {
    public let frameCount: Int
    public private(set) var index = 0
    public private(set) var isPlaying = true

    public init(frameCount: Int) {
        self.frameCount = max(1, frameCount)
    }

    /// Records the frame the player is showing.
    public mutating func show(_ frame: Int) {
        index = ((frame % frameCount) + frameCount) % frameCount
    }

    public mutating func togglePlaying() {
        isPlaying.toggle()
    }

    /// Steps `count` frames (negative goes back) and pauses, as frame step
    /// is for looking at one frame.
    public mutating func step(_ count: Int) {
        isPlaying = false
        show(index + count)
    }

    /// Where playback resumes: the frame after the one shown.
    public var resumeIndex: Int { (index + 1) % frameCount }

    /// `frame 3/12` for toasts and the info panel, one-based.
    public var label: String { "frame \(index + 1)/\(frameCount)" }
}
