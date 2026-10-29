// Gamepad buttons to menu events. The install's control map, context "Menu Mode", binds
// Accept to A (0x1000), Cancel to B (0x2000), the D-pad to Up, Down, Left, and Right, and
// the left stick (0x000b) to move; "Item Menus" binds XButton to X and YButton to Y.

import simd

/// The gamepad buttons a menu reads.
nonisolated public enum GamepadButton: Hashable, Sendable, CaseIterable {
    case a, b, x, y, dpadUp, dpadDown, dpadLeft, dpadRight
}

/// One frame of every connected gamepad together, read by the app.
nonisolated public struct GamepadSnapshot: Equatable, Sendable {
    public var pressed: Set<GamepadButton>
    /// The left stick, -1 to 1; positive y is up.
    public var leftStick: SIMD2<Float>

    public init(pressed: Set<GamepadButton> = [], leftStick: SIMD2<Float> = .zero) {
        self.pressed = pressed
        self.leftStick = leftStick
    }

    /// Two gamepads at once: every pressed button, and the stick pushed furthest.
    public func merged(with other: Self) -> Self {
        let stick = simd_length(other.leftStick) > simd_length(leftStick)
            ? other.leftStick : leftStick
        return Self(pressed: pressed.union(other.pressed), leftStick: stick)
    }
}

/// Turns gamepad snapshots into the menu events the keyboard also sends. A held
/// direction repeats, as a held arrow key does.
nonisolated public struct GamepadMenuInput: Sendable {
    /// How far the stick must lean to move, and how far back it must come to stop.
    public static let stickPress: Float = 0.5
    public static let stickRelease: Float = 0.3
    public static let repeatDelay = 0.5
    public static let repeatInterval = 0.12

    private var heldButtons: Set<GamepadButton> = []
    private var heldDirection: MenuInputEvent.Direction?
    private var nextRepeat = 0.0

    public init() {}

    /// The events since the last snapshot. `now` is in seconds, for the repeat.
    public mutating func events(for snapshot: GamepadSnapshot, now: Double) -> [MenuInputEvent] {
        var events: [MenuInputEvent] = []
        let newButtons = snapshot.pressed.subtracting(heldButtons)
        heldButtons = snapshot.pressed
        for button in GamepadButton.allCases where newButtons.contains(button) {
            if let mapped = Self.menuButton(button) {
                events.append(.button(mapped))
            }
        }
        let direction = direction(of: snapshot)
        if direction != heldDirection {
            if let old = heldDirection {
                events.append(.release(old))
            }
            if let direction {
                events.append(.move(direction))
                nextRepeat = now + Self.repeatDelay
            }
            heldDirection = direction
        } else if let direction, now >= nextRepeat {
            events.append(.move(direction))
            nextRepeat = now + Self.repeatInterval
        }
        return events
    }

    private static func menuButton(_ button: GamepadButton) -> MenuInputEvent.Button? {
        switch button {
        case .a: .accept
        case .b: .cancel
        case .x: .xButton
        case .y: .yButton
        case .dpadUp, .dpadDown, .dpadLeft, .dpadRight: nil
        }
    }

    /// The D-pad wins over the stick. The stick keeps its direction until it
    /// falls below `stickRelease`, so a stick resting near the edge does not flicker.
    private func direction(of snapshot: GamepadSnapshot) -> MenuInputEvent.Direction? {
        let pad: [(GamepadButton, MenuInputEvent.Direction)] = [
            (.dpadUp, .up), (.dpadDown, .down), (.dpadLeft, .left), (.dpadRight, .right)
        ]
        if let found = pad.first(where: { snapshot.pressed.contains($0.0) }) {
            return found.1
        }
        let stick = snapshot.leftStick
        if let held = heldDirection, Self.lean(stick, toward: held) >= Self.stickRelease {
            return held
        }
        let horizontal = abs(stick.x) > abs(stick.y)
        let lean = horizontal ? abs(stick.x) : abs(stick.y)
        guard lean >= Self.stickPress else { return nil }
        if horizontal {
            return stick.x > 0 ? .right : .left
        }
        return stick.y > 0 ? .up : .down
    }

    private static func lean(_ stick: SIMD2<Float>, toward direction: MenuInputEvent.Direction)
        -> Float
    {
        switch direction {
        case .up: stick.y
        case .down: -stick.y
        case .left: -stick.x
        case .right: stick.x
        }
    }
}
