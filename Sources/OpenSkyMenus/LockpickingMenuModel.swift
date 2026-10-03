// The lockpicking menu's input side: held keys and pointer motion become one
// frame's pick movement and turn. The bindings are OpenSky's and are listed on
// docs/engine/locks.md.

import OpenSkyInventoryInterface

/// What the player asks of the lock this frame.
nonisolated public struct LockpickingIntent: Equatable, Sendable {
    /// Degrees to move the pick, positive to the right.
    public var pickDelta: Float
    public var turning: Bool

    public init(pickDelta: Float, turning: Bool) {
        self.pickDelta = pickDelta
        self.turning = turning
    }
}

/// Held keys and pointer motion for one lockpicking session.
nonisolated public struct LockpickingMenuControls: Equatable, Sendable {
    /// Pick speed while A or D is held, in degrees per second.
    public static let keyPickSpeed: Float = 90
    /// Pick movement per point of horizontal pointer motion, in degrees.
    public static let pointerPickScale: Float = 0.5

    public private(set) var held: Set<MenuInputEvent.Direction> = []
    public private(set) var cancelRequested = false
    private var pointerDegrees: Float = 0

    public init() {}

    /// Left and right move the pick, up turns the lock, cancel leaves.
    public mutating func handle(_ event: MenuInputEvent) {
        switch event {
        case let .move(direction):
            held.insert(direction)
        case let .release(direction):
            held.remove(direction)
        case let .pointer(deltaX, _):
            pointerDegrees += deltaX * Self.pointerPickScale
        case .button(.cancel):
            cancelRequested = true
        case .button(.accept):
            break
        }
    }

    /// The intent for `seconds` of play. Pointer motion is used up by the call.
    public mutating func intent(seconds: Float) -> LockpickingIntent {
        var keys: Float = 0
        if held.contains(.left) {
            keys -= 1
        }
        if held.contains(.right) {
            keys += 1
        }
        let delta = keys * Self.keyPickSpeed * max(seconds, 0) + pointerDegrees
        pointerDegrees = 0
        return LockpickingIntent(pickDelta: delta, turning: held.contains(.up))
    }
}

/// One frame of the lockpicking menu, as the overlay draws it.
nonisolated public struct LockpickingMenuPresentation: Equatable, Sendable {
    public var title: String
    public var difficulty: LockDifficulty
    /// Degrees from upright, positive to the right.
    public var pickAngle: Float
    public var halfArc: Float
    /// 0 at rest, 1 open.
    public var lockRotation: Float
    /// 1 for a fresh pick, 0 when it breaks.
    public var pickHealth: Float
    public var picksRemaining: Int32
    public var isStraining: Bool

    public init(
        title: String,
        difficulty: LockDifficulty,
        pickAngle: Float,
        halfArc: Float,
        lockRotation: Float,
        pickHealth: Float,
        picksRemaining: Int32,
        isStraining: Bool
    ) {
        self.title = title
        self.difficulty = difficulty
        self.pickAngle = pickAngle
        self.halfArc = halfArc
        self.lockRotation = lockRotation
        self.pickHealth = pickHealth
        self.picksRemaining = picksRemaining
        self.isStraining = isStraining
    }
}

/// Lockpicking sounds, by the editor ID of their `SNDR` descriptor.
nonisolated public enum LockpickingSound: String, CaseIterable, Sendable {
    case enter = "UILockpickingEnter"
    case cylinderTurn = "UILockpickingCylinderTurn"
    case cylinderStop = "UILockpickingCylinderStop"
    case pickBreak = "UILockpickingPickBreak"
    case unlock = "UILockpickingUnlock"
}
