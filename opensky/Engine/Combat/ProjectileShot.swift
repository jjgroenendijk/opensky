// One shot, whatever fired it (issue #471, roadmap item 19.8, scope point 1).
//
// Item 15.5 built the projectile pipeline arrow-shaped: the value handed to
// `ProjectileRuntime.fire` was an `ArcheryShot` carrying a bow's damage and the
// AMMO to take out of the quiver, and the runtime consumed ammunition and stuck
// what landed. A spell projectile flies through the same integrator, the same
// impact query and the same range and lifetime bounds, and differs only in what
// it carries and what happens when it lands.
//
// So there is one shot model and one payload enumeration rather than a second
// flight engine. Everything arrow-only — consuming ammunition, sticking in the
// surface, the bow's draw-scaled launch speed, the archery tilt-up angle — is
// conditional on the payload being an arrow, and stated as such at each site
// instead of being inferred from a nil field.
//
// The tilt is worth calling out because it is a behaviour change nobody would
// otherwise notice: `fBowAimAngle`/`fBowAimAngleThirdPerson` are archery
// settings that lift a bow shot above the reticle to compensate for arrow
// drop, and a spell is not fired from a bow. A spell projectile launches
// straight down the aim ray.
//
// Documented in docs/engine/archery.md and docs/engine/magic.md.

import Foundation

/// What a projectile carries, and therefore what it does when it lands.
nonisolated enum ProjectilePayload: Equatable, Sendable {
    case arrow(ArrowPayload)
    case spell(SpellPayload)

    /// The arrow half, or nil for anything a quiver did not fire.
    var arrow: ArrowPayload? {
        guard case let .arrow(payload) = self else { return nil }
        return payload
    }

    /// The spell half, or nil for anything a hand did not cast.
    var spell: SpellPayload? {
        guard case let .spell(payload) = self else { return nil }
        return payload
    }

    /// Whether a hit by this payload should make its target hostile. An arrow
    /// always; a spell only when its effects are hostile, so a healing spell
    /// cast at a follower does not start a fight.
    var provokes: Bool {
        switch self {
        case .arrow: true
        case let .spell(payload): payload.isHostile
        }
    }
}

/// What an arrow carries: the damage the draw earned, the bow that fired it,
/// and the ammunition to spend and to leave standing in the target.
nonisolated struct ArrowPayload: Equatable, Sendable {
    /// The resolved damage this shot carries. Fixed at launch: the draw is over
    /// by then, and re-deriving it at impact would let a weapon swap mid-flight
    /// change what an arrow already in the air does.
    let damage: ArcheryDamageResult
    /// The WEAP that fired it; nil for a shot with no bow behind it.
    let weapon: FormID?
    /// The AMMO consumed. Nil means "consume nothing", which is what the dev
    /// spawn control fires with so that a developer inspecting a trajectory
    /// does not have to keep a quiver stocked.
    let ammunition: FormID?
}

/// One shot, assembled by whichever runtime fired it and handed to
/// `ProjectileRuntime`.
///
/// A value rather than separate arguments, because every member is resolved at
/// the same moment — the frame the graph fired `arrowRelease`, or the frame a
/// cast was released — and splitting them would let a caller mix one shot's
/// damage with another shot's profile.
nonisolated struct ProjectileShot: Equatable, Sendable {
    let profile: ProjectileProfile
    let payload: ProjectilePayload

    /// A bow's shot: the launch speed scales with the draw and the archery
    /// tilt-up angle applies.
    static func arrow(
        profile: ProjectileProfile,
        damage: ArcheryDamageResult,
        weapon: FormID? = nil,
        ammunition: FormID? = nil
    ) -> ProjectileShot {
        ProjectileShot(
            profile: profile,
            payload: .arrow(ArrowPayload(
                damage: damage, weapon: weapon, ammunition: ammunition
            ))
        )
    }

    /// A cast spell's shot: full launch speed, straight down the aim ray.
    static func spell(profile: ProjectileProfile, payload: SpellPayload) -> ProjectileShot {
        ProjectileShot(profile: profile, payload: .spell(payload))
    }

    /// The AMMO this shot spends, or nil when it spends none. Only an arrow
    /// ever does.
    var consumedAmmunition: FormID? {
        payload.arrow?.ammunition
    }

    /// What the profile's launch speed is multiplied by. A partial draw slows
    /// an arrow; a spell always leaves at the PROJ's own speed.
    var speedScale: Float {
        payload.arrow?.damage.drawFraction ?? 1
    }

    /// Whether the archery tilt-up angle applies to this shot's aim ray.
    var usesArcheryTilt: Bool {
        payload.arrow != nil
    }
}
