// Gamepad snapshots to menu events: button edges, the D-pad, and the stick.

import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

struct GamepadMenuInputTests {
    private func snapshot(_ pressed: Set<GamepadButton> = [], stick: SIMD2<Float> = .zero)
        -> GamepadSnapshot
    {
        GamepadSnapshot(pressed: pressed, leftStick: stick)
    }

    @Test func faceButtonsSendTheMenuButtonsOncePerPress() {
        var input = GamepadMenuInput()
        #expect(input.events(for: snapshot([.a, .y])) == [
            .button(.accept),
            .button(.yButton)
        ])
        #expect(input.events(for: snapshot([.a, .y])).isEmpty)
        #expect(input.events(for: snapshot([.b, .x])) == [
            .button(.cancel),
            .button(.xButton)
        ])
    }

    @Test func aHeldDirectionMovesOnceThenReleases() {
        var input = GamepadMenuInput()
        #expect(input.events(for: snapshot([.dpadDown])) == [.move(.down)])
        #expect(input.events(for: snapshot([.dpadDown])).isEmpty)
        #expect(input.events(for: snapshot()) == [.release(.down)])
    }

    @Test func theStickMovesPastHalfAndHoldsUntilItReturns() {
        var input = GamepadMenuInput()
        #expect(input.events(for: snapshot(stick: [0.4, 0])).isEmpty)
        #expect(input.events(for: snapshot(stick: [-0.8, 0.2])) == [.move(.left)])
        #expect(input.events(for: snapshot(stick: [-0.35, 0])).isEmpty)
        #expect(input.events(for: snapshot(stick: [0, 0.9])) == [
            .release(.left),
            .move(.up)
        ])
        #expect(input.events(for: snapshot(stick: [0, 0.1])) == [.release(.up)])
    }

    @Test func twoGamepadsMergeTheirButtonsAndTheFurthestStick() {
        let first = snapshot([.a], stick: [0.2, 0])
        let second = snapshot([.dpadUp], stick: [0, -0.9])
        let merged = first.merged(with: second)
        #expect(merged.pressed == [.a, .dpadUp])
        #expect(merged.leftStick == [0, -0.9])
    }
}
