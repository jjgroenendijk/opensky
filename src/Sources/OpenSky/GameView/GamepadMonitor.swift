// Reads every connected gamepad once a frame through Apple's Game Controller framework.
// The count goes to the menu movies. In a menu the buttons go to the open menu; outside
// one they play the game. The mapping rules live in `GamepadMenuInput` and
// `GamepadGameplayInput`.

import GameController
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface

final class GamepadMonitor {
    private var input = GamepadMenuInput()
    private var gameplay = GamepadGameplayInput()
    private(set) var count = 0
    private var realCount = 0
    private var menuHeld: Set<GamepadButton> = []
    private var lastPoll: Double?
    /// The last real gamepad went away.
    var onDisconnect: (() -> Void)?
    /// Set by `openskycli game debug gamepad`: gamepads to report when none is real.
    var simulatedCount = 0
    /// Buttons `debug gamepad --press` holds for one frame.
    var simulatedPress: Set<GamepadButton> = []
    /// The 360 Controller setting. Off, the game reads no gamepad at all.
    var isEnabled: () -> Bool = { true }
    /// The bindings the game view uses, with the gamepad column.
    var bindings: () -> InputBindings = { InputBindings() }
    /// Carries out a gameplay action, through the game view's dispatcher.
    var applyEdge: ((GamepadGameplayInput.Edge) -> Void)?
    /// The camera input the sticks move and turn.
    weak var cameraInput: (any CameraInputStatePort)?
    /// The Controls page waiting for a button; true when it took it.
    var onCapturedButton: ((UInt32) -> Bool)?
    /// The last gameplay user event a gamepad pressed, such as `Jump`, for `state menu`.
    private(set) var lastUserEvent: String?

    func poll(now: Double, renderer: any RendererPort, menuMode: any MenuModePort) {
        let dt = Float(min(0.1, max(0, now - (lastPoll ?? now))))
        lastPoll = now
        let enabled = isEnabled()
        let pads = enabled ? GCController.controllers().compactMap(\.extendedGamepad) : []
        if pads.count < realCount, pads.isEmpty, enabled {
            onDisconnect?()
        }
        realCount = pads.count
        let connected = enabled ? max(pads.count, simulatedCount) : 0
        if connected != count {
            count = connected
            renderer.swfGamepadCount = connected
        }
        var snapshot = pads.map(Self.snapshot).reduce(GamepadSnapshot()) { $0.merged(with: $1) }
        snapshot.pressed.formUnion(simulatedPress)
        simulatedPress = []
        guard enabled else {
            cameraInput?.setAnalogMove(.zero)
            return
        }
        if menuMode.isMenuMode {
            pollMenu(snapshot, now: now, menuMode: menuMode)
        } else {
            pollWorld(snapshot, dt: dt)
        }
    }

    private func pollMenu(_ snapshot: GamepadSnapshot, now: Double, menuMode: any MenuModePort) {
        // Buttons held into the menu do not fire again when it closes.
        _ = gameplay.frame(for: snapshot, bindings: bindings())
        cameraInput?.setAnalogMove(.zero)
        let fresh = snapshot.pressed.subtracting(menuHeld)
        menuHeld = snapshot.pressed
        if fresh.contains(where: { onCapturedButton?($0.controlMapCode) == true }) {
            _ = input.events(for: snapshot, now: now)
            return
        }
        for event in input.events(for: snapshot, now: now) {
            _ = menuMode.routeMenuInput(event)
            // The gamepad's A is Activate as well as Accept.
            if event == .button(.accept) {
                _ = menuMode.routeMenuInput(.activate)
            }
        }
    }

    private func pollWorld(_ snapshot: GamepadSnapshot, dt: Float) {
        menuHeld = snapshot.pressed
        _ = input.events(for: snapshot, now: 0)
        let frame = gameplay.frame(for: snapshot, bindings: bindings())
        for edge in frame.edges {
            if edge.phase == .press {
                lastUserEvent = edge.event
            }
            applyEdge?(edge)
        }
        cameraInput?.setAnalogMove(frame.move)
        guard dt > 0, let cameraInput else { return }
        // The camera scales look by the mouse slider; the gamepad has its own range.
        let scale = max(cameraInput.lookScale, 0.01)
        let sensitivity = GamepadGameplayInput.sensitivity(lookScale: scale)
        let rate = gameplay.lookRate(frame.look, dt: dt, sensitivity: sensitivity)
        guard rate != .zero else { return }
        let points = dt / FreeFlyCamera.lookSensitivity / scale
        cameraInput.addLook(right: rate.x * points, up: rate.y * points)
    }

    private static func snapshot(_ pad: GCExtendedGamepad) -> GamepadSnapshot {
        var buttons: [(GCControllerButtonInput, GamepadButton)] = [
            (pad.buttonA, .a), (pad.buttonB, .b), (pad.buttonX, .x), (pad.buttonY, .y),
            (pad.dpad.up, .dpadUp), (pad.dpad.down, .dpadDown),
            (pad.dpad.left, .dpadLeft), (pad.dpad.right, .dpadRight),
            (pad.leftShoulder, .leftShoulder), (pad.rightShoulder, .rightShoulder),
            (pad.leftTrigger, .leftTrigger), (pad.rightTrigger, .rightTrigger),
            (pad.buttonMenu, .start)
        ]
        if let thumb = pad.leftThumbstickButton {
            buttons.append((thumb, .leftThumb))
        }
        if let thumb = pad.rightThumbstickButton {
            buttons.append((thumb, .rightThumb))
        }
        if let options = pad.buttonOptions {
            buttons.append((options, .back))
        }
        let threshold = GamepadGameplayInput.triggerThreshold
        return GamepadSnapshot(
            pressed: Set(buttons.filter { $0.0.value > threshold || $0.0.isPressed }.map(\.1)),
            leftStick: SIMD2(pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value),
            rightStick: SIMD2(pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value)
        )
    }
}
