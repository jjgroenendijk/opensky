import OpenSkyBehavior
import OpenSkyPhysics
import simd

/// One frame of player intent, in the form the bridge consumes. Filled from
/// `CameraInput` once per frame and held across the fixed steps that frame
/// drives, exactly like the rest of `CameraInput`.
nonisolated public struct LocomotionIntent: Equatable, Sendable {
    /// Along the level view forward vector, [-1, 1].
    public var moveForward: Float = 0
    /// Along the level view right vector, [-1, 1].
    public var moveRight: Float = 0
    /// Run key (Shift) held.
    public var run = false
    /// Sprint key held.
    public var sprint = false
    /// Sneak toggle state.
    public var sneak = false
    /// One jump press, consumed by the first step that can act on it.
    public var jump = false

    public static let still = LocomotionIntent()

    public init(
        moveForward: Float = 0,
        moveRight: Float = 0,
        run: Bool = false,
        sprint: Bool = false,
        sneak: Bool = false,
        jump: Bool = false
    ) {
        self.moveForward = moveForward
        self.moveRight = moveRight
        self.run = run
        self.sprint = sprint
        self.sneak = sneak
        self.jump = jump
    }
}
