// Which actor the crosshair is pointing at, for the Talk activation that opens
// the dialogue menu (issue #205, roadmap item 17.3, scope point 1).
//
// ## Why this is not the interaction raycast
//
// `InteractionRaycaster` answers against `StaticCollisionShape`, the per-cell
// NIF collision geometry the streaming BVH indexes. Actors are not in it: an
// ACHR is built by `CellSceneBuilderActors` on a path that produces no placed
// collision and no `PlacedInteraction`, and it moves every frame besides, which
// is the opposite of what an immutable per-cell BVH is for. Adding actor bodies
// to that structure would mean rebuilding it whenever anybody took a step.
//
// The other machinery already in the engine answers the same question about
// actors every frame: melee resolves a swing against `MeleeTarget` capsules
// through `MeleeHitDetector`, whose `closestApproach` is the exact
// segment-to-segment narrowphase. A view ray is a segment, so this file reuses
// that primitive rather than adding a third way to intersect an actor. The
// M16 perception line of sight (`PerceptionSight`) was the other candidate and
// was not taken: it answers "can this observer see that actor", which is a
// question about one named pair, whereas targeting has to rank every resident
// actor against one ray. The reuse is recorded in docs/engine/dialogue-menu.md.
//
// ## Occlusion
//
// Nothing here tests for a wall. The caller owns that, because it is the one
// holding both answers: `CellStreamer.updateInteractionTarget(ray:)` takes the
// talk hit only when it is nearer than the nearest solid hit along the same
// ray, so a shopkeeper behind a closed door is not a target. Doing it here
// would mean this file querying the collision broad phase, which is exactly the
// coupling the split above avoids.

import simd

/// The streamer's Talk seam: who is a candidate, who is currently picked, and
/// where an activation goes (issue #205).
///
/// One value rather than three properties on `CellStreamer` because they are
/// three parts of one thing, and because the streamer's own body is what a
/// reader of that file is there for.
@MainActor
struct TalkTargetingSeam {
    /// The resident actors the view ray may pick up, sampled once per targeting
    /// pass. A seam rather than a walk over `residentActorEntries()` inside the
    /// streamer, because who is worth talking to is a question about death,
    /// hostility and the world-state components the app owns, not about
    /// streaming. Nil in a session that never wired it, which is every session
    /// before the dialogue layer and every test that does not care.
    var candidateSource: (() -> [TalkCandidate])?
    /// Fires when the use key activates a Talk target. Multicast for the same
    /// reason `CellStreamer.onInteraction` is: the dialogue menu subscribes
    /// here and item 17.4's camera is the next subscriber.
    let activations = CallbackFanOut<TalkActivationEvent>()
    /// The actor the current interaction target names, retained from the pick
    /// so activation does not have to resolve it again.
    var speaker: ReferenceKey?
}

/// One actor the crosshair may pick up, in the shape targeting needs and no
/// other. Deliberately not `CombatActorObservation`: that type carries a
/// facing, a scale and a death latch because a swing needs them, and it carries
/// no `FormID`, which a `PlacedInteraction` does. The app builds these from the
/// same resident-actor walk that builds those.
nonisolated struct TalkCandidate: Equatable, Sendable {
    /// Session-stable identity, which is what a dialogue-entry event carries
    /// and what said-state and the speaker's runtime state are filed under.
    let key: ReferenceKey
    /// The placed ACHR, so the picked actor can ride in a `PlacedInteraction`
    /// beside every other crosshair target.
    let reference: FormID
    /// Its NPC_ record.
    let base: FormID
    /// Capsule bottom, world space, in the same convention `MeleeTarget` uses.
    let feet: SIMD3<Float>
    /// Capsule dimensions. Actors share the player's, as they do in melee:
    /// nothing in this engine resolves a per-race capsule yet.
    let capsule: PlayerCapsule
    /// FULL name when one resolves, else something that still names the actor.
    /// Never empty, so the crosshair prompt always reads as a sentence.
    let name: String

    init(
        key: ReferenceKey,
        reference: FormID,
        base: FormID,
        feet: SIMD3<Float>,
        capsule: PlayerCapsule = .standard,
        name: String
    ) {
        self.key = key
        self.reference = reference
        self.base = base
        self.feet = feet
        self.capsule = capsule
        self.name = name
    }

    /// The capsule's core segment, bottom cap centre to top cap centre — the
    /// same construction `MeleeTarget.segment` makes, so a ray and a swing
    /// agree on where an actor is.
    var segment: (first: SIMD3<Float>, second: SIMD3<Float>) {
        MeleeTarget(key: key, feet: feet, capsule: capsule).segment
    }
}

/// Where a view ray met one actor.
nonisolated struct TalkHit: Equatable, Sendable {
    let candidate: TalkCandidate
    /// Travel along the ray at the closest approach, world units. This is the
    /// nearest point on the ray to the capsule's axis rather than the point the
    /// ray entered the capsule at, which is the same simplification
    /// `MeleeHitDetector` makes and is invisible at a crosshair prompt's
    /// resolution.
    let distance: Float
    /// Midpoint of that closest approach, world space.
    let position: SIMD3<Float>
}

nonisolated enum TalkTargetPicker {
    /// How far a conversation can be started from.
    ///
    /// The interaction ray's own reach rather than a second number: OpenSky has
    /// measured no separate talk distance out of the install, and inventing one
    /// would mean an actor the crosshair reports as a target that the use key
    /// then refuses. Stated here rather than hidden in a default argument so
    /// the assumption is one line to find and one line to change when a GMST
    /// answers it.
    static let defaultMaximumDistance = InteractionRay.defaultMaximumDistance

    /// The nearest actor `ray` passes through, or nil when it passes through
    /// none within `maximumDistance`.
    ///
    /// Ties break on the lower reference, for the reason `MeleeHitDetector`
    /// breaks them there: two actors standing in the same doorway must come
    /// back in the same order every frame or the prompt flickers between them.
    static func nearest(
        ray: InteractionRay,
        candidates: [TalkCandidate],
        maximumDistance: Float = defaultMaximumDistance
    ) -> TalkHit? {
        let reach = min(ray.maximumDistance, max(0, maximumDistance))
        guard reach > 0 else { return nil }
        var best: TalkHit?
        for candidate in candidates {
            guard let hit = touch(ray: ray, reach: reach, candidate: candidate) else {
                continue
            }
            if shouldReplace(best, with: hit) {
                best = hit
            }
        }
        return best
    }

    /// Where one capsule meets the ray, or nil when it does not.
    private static func touch(
        ray: InteractionRay,
        reach: Float,
        candidate: TalkCandidate
    ) -> TalkHit? {
        let radius = max(candidate.capsule.radius, 0)
        guard radius > 0 else { return nil }
        let closest = MeleeHitDetector.closestApproach(
            first: (ray.origin, ray.origin + ray.direction * reach),
            second: candidate.segment
        )
        guard simd_distance(closest.onFirst, closest.onSecond) <= radius else {
            return nil
        }
        let travel = simd_dot(closest.onFirst - ray.origin, ray.direction)
        guard travel.isFinite else { return nil }
        return TalkHit(
            candidate: candidate,
            distance: min(max(travel, 0), reach),
            position: (closest.onFirst + closest.onSecond) * 0.5
        )
    }

    private static func shouldReplace(_ current: TalkHit?, with candidate: TalkHit) -> Bool {
        guard let current else { return true }
        if candidate.distance == current.distance {
            return candidate.candidate.reference.rawValue < current.candidate.reference.rawValue
        }
        return candidate.distance < current.distance
    }
}
