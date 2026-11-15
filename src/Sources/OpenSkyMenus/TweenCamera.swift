// The camera move of the Tween menu: the view widens by 10 degrees and turns a little
// toward the highlighted entry, then eases back on close. Behaviour described from a
// clean-room read of the game; see docs/engine/tween-menu.md#camera.

import OpenSkyMenusInterface
public import OpenSkyRenderCore

nonisolated public struct TweenCamera: Equatable, Sendable {
    static let fovTargetDegrees: Float = 10
    static let fovDegreesPerSecond: Float = 25
    static let openEase: Float = 4
    static let closeEase: Float = 10
    static let turnRadians: Float = 0.05

    public private(set) var offset = MenuViewOffset.none
    /// From open until the view is back where it was after close.
    public private(set) var isActive = false
    private var target = MenuViewOffset.none
    private var isClosing = false

    public init() {}

    mutating func open() {
        isActive = true
        isClosing = false
        offset = .none
        target = MenuViewOffset(horizontalFOVDegrees: Self.fovTargetDegrees)
    }

    /// Turns toward the entry: yaw grows to the left, pitch grows upward.
    mutating func highlight(_ choice: TweenMenuChoice) {
        guard isActive, !isClosing else { return }
        let turn = Self.turnRadians
        (target.yaw, target.pitch) = switch choice {
        case .skills: (0, turn)
        case .magic: (turn, 0)
        case .items: (-turn, 0)
        case .map: (0, -turn)
        }
    }

    mutating func close() {
        guard isActive else { return }
        isClosing = true
        target = .none
    }

    /// The turn eases toward its target; the field of view moves at a fixed rate. Once
    /// closing has brought the field of view back, the move ends.
    mutating func step(dt: Float) {
        guard isActive, dt > 0 else { return }
        let ease = isClosing ? Self.closeEase : Self.openEase
        offset.yaw = Self.eased(offset.yaw, to: target.yaw, by: ease * dt)
        offset.pitch = Self.eased(offset.pitch, to: target.pitch, by: ease * dt)
        let fovGap = target.horizontalFOVDegrees - offset.horizontalFOVDegrees
        let fovStep = Self.fovDegreesPerSecond * dt
        offset.horizontalFOVDegrees = abs(fovGap) <= fovStep
            ? target.horizontalFOVDegrees
            : offset.horizontalFOVDegrees + (fovGap > 0 ? fovStep : -fovStep)
        if isClosing, offset.horizontalFOVDegrees == 0 {
            offset = .none
            isActive = false
            isClosing = false
        }
    }

    /// Moves `share` of the gap, and lands on the target when that would overshoot.
    static func eased(_ value: Float, to target: Float, by share: Float) -> Float {
        share >= 1 ? target : value + (target - value) * share
    }
}
