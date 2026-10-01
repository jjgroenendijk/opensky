// One shot, arrow or spell, through one flight engine. Ammo use, sticking, draw-scaled
// speed and the bow aim tilt (`fBowAimAngle`) apply only to arrow payloads; a spell flies
// straight down the aim ray. See docs/engine/projectiles.md and docs/engine/spell-delivery.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// What a projectile carries, and therefore what it does when it lands.
nonisolated public enum ProjectilePayload: Equatable, Sendable {
    case arrow(ArrowPayload)
    case spell(SpellPayload)

    /// The arrow half, or nil for anything a quiver did not fire.
    public var arrow: ArrowPayload? {
        guard case let .arrow(payload) = self else { return nil }
        return payload
    }

    /// The spell half, or nil for anything a hand did not cast.
    public var spell: SpellPayload? {
        guard case let .spell(payload) = self else { return nil }
        return payload
    }

    /// Whether a hit by this payload should make its target hostile. An arrow
    /// always; a spell only when its effects are hostile, so a healing spell
    /// cast at a follower does not start a fight.
    public var provokes: Bool {
        switch self {
        case .arrow: true
        case let .spell(payload): payload.isHostile
        }
    }
}

/// What an arrow carries: the damage the draw earned, the bow that fired it,
/// and the ammunition to spend and to leave standing in the target.
nonisolated public struct ArrowPayload: Equatable, Sendable {
    /// The resolved damage this shot carries. Fixed at launch: the draw is over
    /// by then, and re-deriving it at impact would let a weapon swap mid-flight
    /// change what an arrow already in the air does.
    public let damage: ArcheryDamageResult
    /// The WEAP that fired it; nil for a shot with no bow behind it.
    public let weapon: FormID?
    /// The AMMO consumed. Nil means "consume nothing", which is what the dev
    /// spawn control fires with so that a developer inspecting a trajectory
    /// does not have to keep a quiver stocked.
    public let ammunition: FormID?
    /// The bow's resolved enchantment, or nil. Fixed at launch like `damage`.
    public let enchantment: ItemEnchantmentProfile?

    public init(
        damage: ArcheryDamageResult,
        weapon: FormID? = nil,
        ammunition: FormID? = nil,
        enchantment: ItemEnchantmentProfile? = nil
    ) {
        self.damage = damage
        self.weapon = weapon
        self.ammunition = ammunition
        self.enchantment = enchantment
    }
}

/// One shot, assembled by whichever runtime fired it. A value, because every member is
/// resolved at one moment and must not be mixed with another shot's.
nonisolated public struct ProjectileShot: Equatable, Sendable {
    public let profile: ProjectileProfile
    public let payload: ProjectilePayload

    /// A bow's shot: the launch speed scales with the draw and the archery
    /// tilt-up angle applies.
    public static func arrow(
        profile: ProjectileProfile,
        damage: ArcheryDamageResult,
        weapon: FormID? = nil,
        ammunition: FormID? = nil,
        enchantment: ItemEnchantmentProfile? = nil
    ) -> ProjectileShot {
        ProjectileShot(
            profile: profile,
            payload: .arrow(ArrowPayload(
                damage: damage,
                weapon: weapon,
                ammunition: ammunition,
                enchantment: enchantment
            ))
        )
    }

    /// A cast spell's shot: full launch speed, straight down the aim ray.
    public static func spell(profile: ProjectileProfile, payload: SpellPayload) -> ProjectileShot {
        ProjectileShot(profile: profile, payload: .spell(payload))
    }

    /// The AMMO this shot spends, or nil when it spends none. Only an arrow
    /// ever does.
    public var consumedAmmunition: FormID? {
        payload.arrow?.ammunition
    }

    /// What the profile's launch speed is multiplied by. A partial draw slows
    /// an arrow; a spell always leaves at the PROJ's own speed.
    public var speedScale: Float {
        payload.arrow?.damage.drawFraction ?? 1
    }

    /// Whether the archery tilt-up angle applies to this shot's aim ray.
    public var usesArcheryTilt: Bool {
        payload.arrow != nil
    }
}
