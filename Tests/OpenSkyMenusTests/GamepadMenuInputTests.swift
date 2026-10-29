// Gamepad snapshots to menu events: button edges, the D-pad and stick, and the repeat.

import OpenSkyMenus
import Testing

struct GamepadMenuInputTests {
    private func snapshot(_ pressed: Set<GamepadButton> = [], stick: SIMD2<Float> = .zero)
        -> GamepadSnapshot
    {
        GamepadSnapshot(pressed: pressed, leftStick: stick)
    }

    @Test func faceButtonsSendTheMenuButtonsOncePerPress() {
        var input = GamepadMenuInput()
        #expect(input.events(for: snapshot([.a, .y]), now: 0) == [
            .button(.accept),
            .button(.yButton)
        ])
        #expect(input.events(for: snapshot([.a, .y]), now: 0.1).isEmpty)
        #expect(input.events(for: snapshot([.b, .x]), now: 0.2) == [
            .button(.cancel),
            .button(.xButton)
        ])
    }

    @Test func aHeldDirectionMovesThenRepeatsThenReleases() {
        var input = GamepadMenuInput()
        #expect(input.events(for: snapshot([.dpadDown]), now: 0) == [.move(.down)])
        #expect(input.events(for: snapshot([.dpadDown]), now: 0.3).isEmpty)
        #expect(input.events(for: snapshot([.dpadDown]), now: 0.5) == [.move(.down)])
        #expect(input.events(for: snapshot([.dpadDown]), now: 0.55).isEmpty)
        #expect(input.events(for: snapshot([.dpadDown]), now: 0.63) == [.move(.down)])
        #expect(input.events(for: snapshot(), now: 0.7) == [.release(.down)])
    }

    @Test func theStickMovesPastHalfAndHoldsUntilItReturns() {
        var input = GamepadMenuInput()
        #expect(input.events(for: snapshot(stick: [0.4, 0]), now: 0).isEmpty)
        #expect(input.events(for: snapshot(stick: [-0.8, 0.2]), now: 0.1) == [.move(.left)])
        #expect(input.events(for: snapshot(stick: [-0.35, 0]), now: 0.2).isEmpty)
        #expect(input.events(for: snapshot(stick: [0, 0.9]), now: 0.3) == [
            .release(.left),
            .move(.up)
        ])
        #expect(input.events(for: snapshot(stick: [0, 0.1]), now: 0.4) == [.release(.up)])
    }

    @Test func twoGamepadsMergeTheirButtonsAndTheFurthestStick() {
        let first = snapshot([.a], stick: [0.2, 0])
        let second = snapshot([.dpadUp], stick: [0, -0.9])
        let merged = first.merged(with: second)
        #expect(merged.pressed == [.a, .dpadUp])
        #expect(merged.leftStick == [0, -0.9])
    }
}
