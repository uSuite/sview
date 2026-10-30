import Testing
@testable import SViewCore

struct AnimationStateTests {
    @Test func stepsWrapAndPause() {
        var state = AnimationState(frameCount: 4)
        #expect(state.isPlaying)
        state.step(1)
        #expect(!state.isPlaying)
        #expect(state.index == 1)
        state.step(-3)
        #expect(state.index == 2)
        state.step(9)
        #expect(state.index == 3)
        #expect(state.label == "frame 4/4")
        #expect(state.resumeIndex == 0)
    }

    @Test func toggleAndShow() {
        var state = AnimationState(frameCount: 3)
        state.togglePlaying()
        #expect(!state.isPlaying)
        state.togglePlaying()
        #expect(state.isPlaying)
        state.show(7)
        #expect(state.index == 1)
        #expect(state.resumeIndex == 2)
    }

    @Test func degenerateFrameCount() {
        var state = AnimationState(frameCount: 0)
        #expect(state.frameCount == 1)
        state.step(5)
        #expect(state.index == 0)
    }
}
