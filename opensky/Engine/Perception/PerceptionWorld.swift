// The world seam perception runs over (issue #202, roadmap item 16.6), and the
// values on either side of it.
//
// `CombatLoopWorld`'s shape, for the same reason: every question below is
// something the session already knows how to answer — which resident actors the
// AI is driving, where the player is standing and how it is moving, whether one
// point can see another — and naming them together is what lets the whole pass
// run against a fake world with no renderer, no window and no game data.
//
// ## Why an observer and a target are different types
//
// A vanilla detection pair is not symmetric. The observer contributes a facing,
// a view cone and a perception skill; the target contributes a gait, a crouch
// and an equipped weight. Modelling both as "an actor" would mean carrying six
// fields that mean nothing on one side of the pair and reading them anyway.
//
// The split also states the milestone's scope in the type system. 16.6 is the
// perception half: observers perceive, targets are perceived, and nothing here
// acts on the result. What an alerted actor *does* is 16.7's, and it reads
// `DetectionPairState.lastKnownPosition` to do it.
//
// Documented in docs/engine/detection.md.

import simd

/// One actor that is looking and listening, as the perception pass sees it.
nonisolated struct PerceptionObserver: Equatable, Sendable {
    let key: ReferenceKey
    /// Capsule bottom, world space.
    let feet: SIMD3<Float>
    /// The point sight is traced from: the capsule's eye height above `feet`.
    let eye: SIMD3<Float>
    /// Facing yaw in radians, in the locomotion bridge's convention. The view
    /// cone is centred on it.
    let facing: Float
    /// Whether this observer stands in an exterior cell, which is what
    /// `fSneakExteriorDistanceMult` applies to.
    let isExterior: Bool
    /// FULL name when one resolves, else the editor ID, else the FormID. Never
    /// empty, so a readout line always names something.
    let name: String

    init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        eye: SIMD3<Float>? = nil,
        facing: Float = 0,
        isExterior: Bool = true,
        name: String = "—"
    ) {
        self.key = key
        self.feet = feet
        self.eye = eye ?? (feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight))
        self.facing = facing
        self.isExterior = isExterior
        self.name = name
    }

    /// The unit heading the cone is centred on, in the XY plane. Perception is
    /// a yaw cone rather than a solid angle: nothing in this engine pitches an
    /// actor's head, so a pitch term would only ever read zero.
    var heading: SIMD2<Float> {
        SIMD2(cosf(facing), sinf(facing))
    }
}

/// One actor that may be perceived, as the perception pass sees it.
nonisolated struct PerceptionTarget: Equatable, Sendable {
    let key: ReferenceKey
    /// Capsule bottom, world space.
    let feet: SIMD3<Float>
    /// The point sight is traced to. Tracing to the eye rather than to the feet
    /// is what makes a target behind a waist-high wall still visible.
    let eye: SIMD3<Float>
    /// How the target is moving right now, or nil when it is standing still. A
    /// still target makes no movement noise at all, which is vanilla's own rule
    /// ("This value is simply set to 0 when not moving").
    let gait: LocomotionGait?
    /// Whether the target is crouched. Distinct from `gait == .sneak` because a
    /// motionless crouching target is still harder to see while making no noise.
    let isSneaking: Bool
    /// Combined weight of everything equipped, which the movement-noise term
    /// scales with. Zero is a supported value, not a missing one: it means the
    /// target counts as `equippedWeightBase` alone.
    let equippedWeight: Float
    /// FULL name when one resolves, else the editor ID, else the FormID.
    let name: String

    init(
        key: ReferenceKey,
        feet: SIMD3<Float>,
        eye: SIMD3<Float>? = nil,
        gait: LocomotionGait? = nil,
        isSneaking: Bool = false,
        equippedWeight: Float = 0,
        name: String = "—"
    ) {
        self.key = key
        self.feet = feet
        self.eye = eye ?? (feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight))
        self.gait = gait
        self.isSneaking = isSneaking
        self.equippedWeight = equippedWeight
        self.name = name
    }
}

/// Everything `PerceptionRuntime` needs from the session around it.
@MainActor
protocol PerceptionWorld: AnyObject {
    /// Every actor whose perception is simulated this frame, in `ReferenceKey`
    /// order. The caller's filter, not the runtime's: only the session knows
    /// which resident ACHRs the AI is driving, and simulating the rest would be
    /// work nobody can observe.
    func perceptionObservers() -> [PerceptionObserver]

    /// Every actor that may be perceived, in `ReferenceKey` order.
    func perceptionTargets() -> [PerceptionTarget]

    /// Whether the straight segment from `origin` to `destination` is clear of
    /// static collision.
    ///
    /// An exact ray rather than the projectile sweep: a sight line has no
    /// thickness, so `collisionRadius` would have nothing to put in it, and
    /// `InteractionRaycaster` answers exactly over the same broadphase the
    /// sweep uses. Actors are deliberately not obstacles — a guard behind a
    /// guard can still see you — which is the same choice the interaction ray
    /// makes and is stated on the docs page rather than assumed.
    func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool
}
