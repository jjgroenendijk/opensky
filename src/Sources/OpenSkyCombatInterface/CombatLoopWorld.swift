import OpenSkyBehavior
public import OpenSkyFormatsESM
public import OpenSkyPerceptionInterface
public import OpenSkyPhysics
import simd

/// One resident actor as the combat loop sees it.
///
/// A flat observation rather than a live handle, so the runtime cannot reach
/// past what it was given and a test can hand it a literal.
nonisolated public struct CombatActorObservation: Equatable, Sendable {
    public let key: ReferenceKey
    /// Capsule bottom, world space.
    public let feet: SIMD3<Float>
    public let capsule: PlayerCapsule
    /// The placement's heading in radians: clockwise from north, as `angleZ`.
    public let facing: Float
    /// The same direction as a yaw, counter-clockwise from +X, which the view cone
    /// and the aim of an attack read (docs/engine/player-camera.md).
    public var yaw: Float {
        .pi / 2 - facing
    }

    /// The actor's scale, which multiplies its reach.
    public let scale: Float
    /// Whether `ActorDeathState` has latched. A dead actor is never a combat
    /// target and never attacks.
    public let isDead: Bool
    /// FULL name, editor ID, or key and base form, formatted only when read.
    public let label: ActorLabel

    public var name: String {
        label.text
    }

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        capsule: PlayerCapsule = .standard,
        facing: Float = 0,
        scale: Float = 1,
        isDead: Bool = false,
        name: String = "—"
    ) {
        self.key = key
        self.feet = feet
        self.capsule = capsule
        self.facing = facing
        self.scale = scale
        self.isDead = isDead
        label = ActorLabel(name)
    }

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        facing: Float,
        scale: Float,
        isDead: Bool,
        label: ActorLabel
    ) {
        self.key = key
        self.feet = feet
        capsule = .standard
        self.facing = facing
        self.scale = scale
        self.isDead = isDead
        self.label = label
    }
}
