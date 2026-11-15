// A gamepad outside menus: the control map's gamepad column fires actions on press and
// release, the sticks pass a radial dead zone, and a gamepad remap swaps buttons.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsSWF
@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

struct GamepadGameplayInputTests {
    @Test func aButtonFiresItsActionOnceAndHeldOnesRelease() {
        var input = GamepadGameplayInput()
        let bindings = InputBindings()
        let jump = input.frame(for: GamepadSnapshot(pressed: [.y]), bindings: bindings)
        #expect(jump.edges.map(\.action) == [.jump])
        #expect(jump.edges.first?.event == "Jump")
        #expect(input.frame(for: GamepadSnapshot(pressed: [.y]), bindings: bindings).edges.isEmpty)
        #expect(
            input.frame(for: GamepadSnapshot(), bindings: bindings).edges.isEmpty,
            "Jump has no release"
        )
        _ = input.frame(for: GamepadSnapshot(pressed: [.rightTrigger]), bindings: bindings)
        let release = input.frame(for: GamepadSnapshot(), bindings: bindings)
        #expect(release.edges == [
            GamepadGameplayInput.Edge(action: .attack, phase: .release, event: "Right Attack/Block")
        ])
    }

    @Test func eitherDpadButtonOpensTheFavourites() {
        var input = GamepadGameplayInput()
        let frame = input.frame(
            for: GamepadSnapshot(pressed: [.dpadDown]),
            bindings: InputBindings()
        )
        #expect(frame.edges.map(\.action) == [.favorites])
    }

    @Test func theSticksPassARadialDeadZone() {
        #expect(GamepadGameplayInput.filtered(SIMD2(0.15, 0.15)) == .zero)
        let full = GamepadGameplayInput.filtered(SIMD2(0, 0.97))
        #expect(abs(full.y - 1) < 0.0001)
        let half = GamepadGameplayInput.filtered(SIMD2(0.61, 0))
        #expect(abs(half.x - 0.5) < 0.0001)
    }

    /// A small push walks: 20 % of the travel gives a tenth of run speed.
    @Test func theLeftStickFollowsTheSpeedCurve() {
        #expect(abs(GamepadGameplayInput.movement(SIMD2(0, 0.2)).y - 0.1) < 0.0001)
        #expect(abs(GamepadGameplayInput.movement(SIMD2(-0.7, 0)).x + 0.5) < 0.0001)
        #expect(abs(GamepadGameplayInput.movement(SIMD2(0, 1)).y - 1) < 0.0001)
    }

    /// At the default sensitivity a full push turns about 121 degrees a second, and holding
    /// it all the way speeds the turn up to 2.5 times over 0.92 s.
    @Test func aHeldLookSpeedsUp() {
        var input = GamepadGameplayInput()
        let sensitivity = GamepadGameplayInput.sensitivity(lookScale: 1)
        #expect(abs(sensitivity - 0.66672) < 0.001)
        let start = input.lookRate(SIMD2(1, 0), dt: 0, sensitivity: sensitivity)
        #expect(abs(start.x * 180 / .pi - 121) < 1)
        _ = input.lookRate(SIMD2(1, 0), dt: 0.5, sensitivity: sensitivity)
        let held = input.lookRate(SIMD2(1, 0), dt: 0.5, sensitivity: sensitivity)
        #expect(abs(held.x / start.x - 2.5) < 0.01)
        let small = input.lookRate(SIMD2(0.5, 0.05), dt: 0.1, sensitivity: sensitivity)
        #expect(small.y == 0, "the cross-axis push is snapped away")
        #expect(input.lookRate(.zero, dt: 0.1, sensitivity: sensitivity) == .zero)
    }

    @Test func theFilesGamepadColumnIsTheDefault() throws {
        let text = """
        // Main Gameplay
        Jump\t0x39\t0xff\t0x1000\t1\t1\t1
        Activate\t0x12\t0xff\t0x8000\t1\t1\t1
        Quicksave\t0x3f\t0xff\t0xff\t1\t0\t0

        """
        var bindings = try InputBindings(controlMap: ControlMapFile(data: Data(text.utf8)))
        #expect(bindings.action(forGamepadCode: 0x1000) == .jump)
        #expect(bindings.rebindGamepad(.activate, to: 0x1000) == .swapped(with: .jump))
        #expect(bindings.gamepadCodes(for: .jump) == [0x8000])
        #expect(bindings.rebindGamepad(.quicksave, to: 0x2000) == .notRemappable)
        let saved = bindings.savedBindings
        #expect(saved["Gamepad|Main Gameplay|Activate"] == 0x1000)
        var restored = try InputBindings(controlMap: ControlMapFile(data: Data(text.utf8)))
        restored.restore(saved)
        #expect(restored.gamepadCodes(for: .activate) == [0x1000])
    }

    @Test func gamepadRowsUseTheXboxArt() {
        let rows = SystemMenuMovieBridge.mappingRows(
            InputBindings(),
            keyName: { _ in "" },
            gamepad: true
        )
        let jump = rows.first { $0["text"] == .string("Jump") }
        #expect(jump?["buttonName"] == .string("360_Y"))
        #expect(!rows.contains { $0["text"] == .string("Forward") }, "the stick is not remapped")
        #expect(GamepadButton(controlMapCode: 0x000A) == .rightTrigger)
    }
}
