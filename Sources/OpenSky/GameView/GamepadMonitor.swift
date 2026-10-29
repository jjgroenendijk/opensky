// Reads every connected gamepad once a frame through Apple's Game Controller framework.
// The count goes to the menu movies, and the buttons go to the open menu. The mapping
// rules live in `GamepadMenuInput`.

import GameController
import OpenSkyMenus
import OpenSkyRendering

final class GamepadMonitor {
    private var input = GamepadMenuInput()
    private(set) var count = 0
    /// Set by `openskycli game debug gamepad`: gamepads to report when none is real.
    var simulatedCount = 0
    /// Buttons `debug gamepad --press` holds for one frame.
    var simulatedPress: Set<GamepadButton> = []

    func poll(now: Double, renderer: Renderer, menuMode: MenuModeController) {
        let pads = GCController.controllers().compactMap(\.extendedGamepad)
        let connected = max(pads.count, simulatedCount)
        if connected != count {
            count = connected
            renderer.swfGamepadCount = connected
        }
        var snapshot = pads.map(Self.snapshot).reduce(GamepadSnapshot()) { $0.merged(with: $1) }
        snapshot.pressed.formUnion(simulatedPress)
        simulatedPress = []
        let events = input.events(for: snapshot, now: now)
        guard menuMode.isMenuMode else { return }
        for event in events {
            _ = menuMode.routeMenuInput(event)
        }
    }

    private static func snapshot(_ pad: GCExtendedGamepad) -> GamepadSnapshot {
        let buttons: [(GCControllerButtonInput, GamepadButton)] = [
            (pad.buttonA, .a), (pad.buttonB, .b), (pad.buttonX, .x), (pad.buttonY, .y),
            (pad.dpad.up, .dpadUp), (pad.dpad.down, .dpadDown),
            (pad.dpad.left, .dpadLeft), (pad.dpad.right, .dpadRight)
        ]
        let stick = pad.leftThumbstick
        return GamepadSnapshot(
            pressed: Set(buttons.filter(\.0.isPressed).map(\.1)),
            leftStick: SIMD2(stick.xAxis.value, stick.yAxis.value)
        )
    }
}
