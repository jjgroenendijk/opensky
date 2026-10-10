// The world seam perception runs over, shaped like `CombatLoopWorld`, so the
// pass runs against a fake world with no renderer or game data. Observer and
// target are different types because a detection pair is not symmetric: one
// side has a facing and a perception skill, the other a gait and a crouch.
// See docs/engine/detection.md.

import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

/// One actor that is looking and listening, as the perception pass sees it.
nonisolated public struct PerceptionObserver: Equatable, Sendable {
    public let key: ReferenceKey
    /// Capsule bottom, world space.
    public let feet: SIMD3<Float>
    /// The point sight is traced from: the capsule's eye height above `feet`.
    public let eye: SIMD3<Float>
    /// Facing yaw in radians, in the locomotion bridge's convention. The view
    /// cone is centred on it.
    public let facing: Float
    /// Whether this observer stands in an exterior cell, which is what
    /// `fSneakExteriorDistanceMult` applies to.
    public let isExterior: Bool
    /// FULL name, editor ID, or key and base form, formatted only when read.
    public let label: ActorLabel
    /// The observer's Sneak skill: a skilled observer notices more.
    public let sneakSkill: Float

    public var name: String {
        label.text
    }

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        eye: SIMD3<Float>? = nil,
        facing: Float = 0,
        isExterior: Bool = true,
        name: String = "—",
        sneakSkill: Float = DetectionTargetTraits.startingSkill
    ) {
        self.init(
            key: key, feet: feet, eye: eye, facing: facing, isExterior: isExterior,
            label: ActorLabel(name), sneakSkill: sneakSkill
        )
    }

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        eye: SIMD3<Float>?,
        facing: Float,
        isExterior: Bool,
        label: ActorLabel,
        sneakSkill: Float = DetectionTargetTraits.startingSkill
    ) {
        self.key = key
        self.feet = feet
        self.eye = eye ?? (feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight))
        self.facing = facing
        self.isExterior = isExterior
        self.label = label
        self.sneakSkill = sneakSkill
    }

    /// The unit heading the cone is centred on, in the XY plane. Perception is
    /// a yaw cone rather than a solid angle: nothing in this engine pitches an
    /// actor's head, so a pitch term would only ever read zero.
    public var heading: SIMD2<Float> {
        SIMD2(cosf(facing), sinf(facing))
    }
}

/// One actor that may be perceived, as the perception pass sees it.
nonisolated public struct PerceptionTarget: Equatable, Sendable {
    public let key: ReferenceKey
    /// Capsule bottom, world space.
    public let feet: SIMD3<Float>
    /// The point sight is traced to. Tracing to the eye rather than to the feet
    /// is what makes a target behind a waist-high wall still visible.
    public let eye: SIMD3<Float>
    /// How the target is moving right now, or nil when it is standing still. A
    /// still target makes no movement noise at all, which is vanilla's own rule
    /// ("This value is simply set to 0 when not moving").
    public let gait: LocomotionGait?
    /// Whether the target is crouched. Distinct from `gait == .sneak` because a
    /// motionless crouching target is still harder to see while making no noise.
    public let isSneaking: Bool
    /// Armour, light, muffle, action noise, skill, and invisibility.
    public let traits: DetectionTargetTraits
    /// FULL name when one resolves, else the editor ID, else the FormID.
    public let name: String

    public init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        eye: SIMD3<Float>? = nil,
        gait: LocomotionGait? = nil,
        isSneaking: Bool = false,
        traits: DetectionTargetTraits = .neutral,
        name: String = "—"
    ) {
        self.key = key
        self.feet = feet
        self.eye = eye ?? (feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight))
        self.gait = gait
        self.isSneaking = isSneaking
        self.traits = traits
        self.name = name
    }
}

/// Everything `PerceptionRuntime` needs from the session around it.
@MainActor
public protocol PerceptionWorld: AnyObject {
    /// Every actor whose perception is simulated this frame, in `ReferenceKey`
    /// order. The caller's filter, not the runtime's: only the session knows
    /// which resident ACHRs the AI is driving, and simulating the rest would be
    /// work nobody can observe.
    func perceptionObservers() -> [PerceptionObserver]

    /// Every actor that may be perceived, in `ReferenceKey` order.
    func perceptionTargets() -> [PerceptionTarget]

    /// Whether the segment from `origin` to `destination` is clear of static
    /// collision. An exact ray, because a sight line has no thickness. Actors are
    /// not obstacles: a guard behind a guard can still see you.
    func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool
}
