// Which actor the crosshair points at, for Talk. Actors are not in the static collision
// BVH, so this reuses the melee capsule test (`MeleeHitDetector.closestApproach`) with
// the view ray as the segment. The caller handles walls: `updateInteractionTarget(ray:)`
// keeps the talk hit only when it is nearer than the solid hit.
// See docs/engine/dialogue-menu.md.

import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldInterface
import simd

/// The streamer's Talk seam: the candidates, the current pick, and where an activation
/// goes. One value, because the three parts belong together.
@MainActor
public struct TalkTargetingSeam {
    /// The resident actors the view ray may pick up, sampled once per targeting
    /// pass. A seam rather than a walk over `residentActorEntries()` inside the
    /// streamer, because who is worth talking to is a question about death,
    /// hostility and the world-state components the app owns, not about
    /// streaming. Nil in a session that never wired it, which is every session
    /// before the dialogue layer and every test that does not care.
    public var candidateSource: (() -> [TalkCandidate])?
    /// Fires when the use key activates a Talk target. Multicast like
    /// `CellStreamer.onInteraction`: the dialogue menu and dialogue camera subscribe.
    public let activations = CallbackFanOut<TalkActivationEvent>()
    /// The actor the current interaction target names, retained from the pick
    /// so activation does not have to resolve it again.
    public var speaker: ReferenceKey?
}

/// One actor the crosshair may pick up, in the shape targeting needs and no
/// other. Deliberately not `CombatActorObservation`: that type carries a
/// facing, a scale and a death latch because a swing needs them, and it carries
/// no `FormID`, which a `PlacedInteraction` does. The app builds these from the
/// same resident-actor walk that builds those.
nonisolated public struct TalkCandidate: Equatable, Sendable {
    /// Session-stable identity, which is what a dialogue-entry event carries
    /// and what said-state and the speaker's runtime state are filed under.
    public let key: ReferenceKey
    /// The placed ACHR, so the picked actor can ride in a `PlacedInteraction`
    /// beside every other crosshair target.
    public let reference: FormID
    /// Its NPC_ record.
    public let base: FormID
    /// Capsule bottom, world space, in the same convention `MeleeTarget` uses.
    public let feet: SIMD3<Float>
    /// Capsule dimensions. Actors share the player's, as they do in melee:
    /// nothing in this engine resolves a per-race capsule yet.
    public let capsule: PlayerCapsule
    /// FULL name when one resolves, else something that still names the actor.
    /// Never empty, so the crosshair prompt always reads as a sentence.
    public let name: String

    public init(
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
    public var segment: (first: SIMD3<Float>, second: SIMD3<Float>) {
        MeleeTarget(key: key, feet: feet, capsule: capsule).segment
    }
}

/// Where a view ray met one actor.
nonisolated public struct TalkHit: Equatable, Sendable {
    public let candidate: TalkCandidate
    /// Travel along the ray at the closest approach, world units. This is the
    /// nearest point on the ray to the capsule's axis rather than the point the
    /// ray entered the capsule at, which is the same simplification
    /// `MeleeHitDetector` makes and is invisible at a crosshair prompt's
    /// resolution.
    public let distance: Float
    /// Midpoint of that closest approach, world space.
    public let position: SIMD3<Float>
}

nonisolated public enum TalkTargetPicker: Sendable {
    /// How far a conversation can start from: the interaction ray's reach. No talk
    /// distance is known from the install, and a second number would let the crosshair
    /// pick an actor the use key then refuses.
    public static let defaultMaximumDistance = InteractionRay.defaultMaximumDistance

    /// The nearest actor `ray` passes through, or nil when it passes through
    /// none within `maximumDistance`.
    ///
    /// Ties break on the lower reference, for the reason `MeleeHitDetector`
    /// breaks them there: two actors standing in the same doorway must come
    /// back in the same order every frame or the prompt flickers between them.
    public static func nearest(
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
