// CameraInputState press/release -> axis logic + look-delta draining (todo
// 2.8). AppKit-free, so fully unit-testable.

@testable import opensky
import Testing

struct CameraInputStateTests {
    @Test
    func heldKeysMapToAxes() {
        let state = CameraInputState()
        state.press(.forward)
        state.press(.right)
        state.press(.up)
        let input = state.makeInput(dt: 1)
        #expect(input.moveForward == 1)
        #expect(input.moveRight == 1)
        #expect(input.moveUp == 1)
    }

    @Test
    func opposingKeysCancel() {
        let state = CameraInputState()
        state.press(.forward)
        state.press(.back)
        let input = state.makeInput(dt: 1)
        #expect(input.moveForward == 0)
    }

    @Test
    func releaseClearsAxis() {
        let state = CameraInputState()
        state.press(.left)
        state.release(.left)
        #expect(state.makeInput(dt: 1).moveRight == 0)
    }

    @Test
    func boostFlows() {
        let state = CameraInputState()
        state.setBoost(true)
        #expect(state.makeInput(dt: 1).boost)
        state.setBoost(false)
        #expect(!state.makeInput(dt: 1).boost)
    }

    @Test
    func lookDeltasAccumulateThenDrain() {
        let state = CameraInputState()
        state.addLook(right: 3, up: -2)
        state.addLook(right: 1, up: 5)
        let first = state.makeInput(dt: 1)
        #expect(first.lookRight == 4)
        #expect(first.lookUp == 3)
        // Drained: next frame with no motion is zero.
        let second = state.makeInput(dt: 1)
        #expect(second.lookRight == 0)
        #expect(second.lookUp == 0)
    }

    @Test
    func releaseAllClearsEverything() {
        let state = CameraInputState()
        state.press(.forward)
        state.setBoost(true)
        state.addLook(right: 10, up: 10)
        state.releaseAll()
        let input = state.makeInput(dt: 1)
        #expect(input.moveForward == 0)
        #expect(!input.boost)
        #expect(input.lookRight == 0)
        #expect(input.lookUp == 0)
    }

    @Test
    func dtPassesThrough() {
        #expect(CameraInputState().makeInput(dt: 0.016).dt == 0.016)
    }

    @Test
    func activationLatchesUntilConsumed() {
        let state = CameraInputState()
        state.requestActivation()
        _ = state.makeInput(dt: 0.016)
        #expect(state.consumeActivation())
        #expect(!state.consumeActivation())
    }
}
