// A gamepad outside menus: the control map's gamepad column fires the gameplay
// actions, the left stick moves, and the right stick turns the view
// (docs/engine/as2-input.md, "Gamepads in the world").

import Foundation
public import OpenSkyMenusInterface
import simd

nonisolated public struct GamepadGameplayInput: Sendable {
    /// One frame of gamepad play: the button edges, then the sticks after the dead zone.
    public struct Frame: Equatable, Sendable {
        public var edges: [Edge] = []
        /// x is right, y is forward, each -1 to 1.
        public var move: SIMD2<Float> = .zero
        /// x turns right, y looks up, each -1 to 1.
        public var look: SIMD2<Float> = .zero
    }

    public struct Edge: Equatable, Sendable {
        public let action: GameInputAction
        public let phase: GameInputPhase
        /// The control map user event, such as `Jump`, for the state read.
        public let event: String
    }

    /// A stick reads as centred below 25 % of its travel and as full from 97 %.
    public static let innerDeadZone: Float = 0.25
    public static let outerDeadZone: Float = 0.97
    /// A trigger presses its attack above 5 % of its travel.
    public static let triggerThreshold: Float = 0.05
    /// The gamepad look sensitivity at the middle of the slider, and its range.
    public static let defaultSensitivity: Float = 0.66672
    public static let sensitivityRange: ClosedRange<Float> = 0.4445 ... 1.5556

    private var held: Set<UInt32> = []
    /// Seconds the right stick has been pushed all the way.
    private var pegged: Float = 0

    public init() {}

    public mutating func frame(
        for snapshot: GamepadSnapshot, bindings: InputBindings
    ) -> Frame {
        let pressed = Set(snapshot.pressed.map(\.controlMapCode))
        var frame = Frame()
        for slot in InputBindings.slots where slot.context == .gameplay {
            let codes = Set(bindings.gamepadCodes(for: slot.action))
            guard !codes.isEmpty else { continue }
            let now = !codes.isDisjoint(with: pressed)
            let before = !codes.isDisjoint(with: held)
            if now, !before {
                frame.edges.append(Edge(action: slot.action, phase: .press, event: slot.event))
            } else if before, !now, slot.action.sendsRelease {
                frame.edges.append(Edge(action: slot.action, phase: .release, event: slot.event))
            }
        }
        held = pressed
        frame.move = Self.movement(Self.filtered(snapshot.leftStick))
        frame.look = Self.filtered(snapshot.rightStick)
        return frame
    }

    /// A radial dead zone, so a diagonal keeps its direction near the centre.
    static func filtered(_ stick: SIMD2<Float>) -> SIMD2<Float> {
        let length = simd_length(stick)
        guard length > innerDeadZone else { return .zero }
        let scaled = min(1, (length - innerDeadZone) / (outerDeadZone - innerDeadZone))
        return stick / length * scaled
    }

    /// The share of run speed a left stick push gives: slow near the centre, a straight
    /// line between the points of `movementCurve`.
    static func movement(_ stick: SIMD2<Float>) -> SIMD2<Float> {
        let length = min(1, simd_length(stick))
        guard length > 0 else { return .zero }
        let points: [SIMD2<Float>] = [[0, 0], [0.2, 0.1], [0.7, 0.5], [0.9, 0.9], [1, 1]]
        var speed: Float = 1
        for (low, high) in zip(points, points.dropFirst()) where length <= high.x {
            speed = low.y + (high.y - low.y) * (length - low.x) / (high.x - low.x)
            break
        }
        return stick / simd_length(stick) * speed
    }

    /// The gamepad look sensitivity for the camera's look scale, which is 1 at the middle
    /// of OpenSky's Look Sensitivity slider.
    public static func sensitivity(lookScale: Float) -> Float {
        min(
            max(defaultSensitivity * lookScale, sensitivityRange.lowerBound),
            sensitivityRange.upperBound
        )
    }

    /// Radians a second the view turns, x to the right and y up. A stick held all the way
    /// speeds the turn up over about a second (docs/engine/as2-input.md).
    public mutating func lookRate(
        _ look: SIMD2<Float>, dt: Float, sensitivity: Float
    ) -> SIMD2<Float> {
        pegged = abs(simd_length_squared(look) - 1) <= 0.0001 ? pegged + dt : 0
        let snapped = Self.snappedToAxis(look)
        let magnitude = simd_length(snapped)
        guard magnitude > 0.000001 else { return .zero }
        let curved = snapped / magnitude * Self.responseCurve(magnitude)
        let ratio = Self.defaultSensitivity / max(sensitivity, 0.01)
        let rampTime = 0.92 * ratio
        let peak = max(2.5 * ratio, 1)
        let boost = 1 + (peak - 1) * min(pegged, rampTime) / rampTime
        let scaled = curved * boost * sensitivity
        return SIMD2(scaled.x * .pi, scaled.y * 0.5625 * 3)
    }

    /// Takes a small push on the other axis away, so a mostly level push turns level.
    static func snappedToAxis(_ look: SIMD2<Float>) -> SIMD2<Float> {
        func snap(_ value: Float, other: Float) -> Float {
            let cut = min(abs(other), 0.15)
            let kept = max(abs(value) - cut, 0) / (1 - cut)
            return value < 0 ? -kept : kept
        }
        return SIMD2(snap(look.x, other: look.y), snap(look.y, other: look.x))
    }

    /// Slow for a small push and fast near the edge, close to a cube.
    static func responseCurve(_ magnitude: Float) -> Float {
        let terms: [Float] = [0.115141, -0.382666, 2.02865, -0.754499]
        return terms.reversed().reduce(0) { ($0 + $1) * magnitude }
    }
}
