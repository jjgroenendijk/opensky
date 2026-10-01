// A swing's shape and reach: reach = fCombatDistance * actorScale * WEAP.reach (UESP WEAP;
// xEdit). Without a WEAP it falls back to bare `fCombatDistance`. The volume is a swept
// capsule from the facing at the contact frame, not the animation pose, so it may hit
// early but never late. See docs/engine/melee-combat.md.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

/// Everything a swing needs to know about the weapon making it.
nonisolated public struct MeleeWeaponProfile: Equatable, Sendable {
    /// WEAP DATA base damage.
    public let damage: Float
    /// WEAP DNAM `reach` multiplier.
    public let reach: Float
    /// WEAP DNAM `speed`, written to `weaponSpeedMult`.
    public let speed: Float
    /// WEAP DNAM `stagger` magnitude, written to `staggerMagnitude` on the
    /// target's graph.
    public let stagger: Float
    /// The WEAP itself, for the readout and the impact-data lookup. Nil for an
    /// unarmed swing.
    public let weapon: FormID?
    /// BIDS — the impact data set the hit resolves its sound through.
    public let impactDataSet: FormID?
    /// Which animation set the graph plays for this weapon, written to `iRightHandType`.
    public let handType: CombatHandType
    /// The weapon's resolved enchantment, or nil. Fixed at equip time, so a swing applies
    /// what the weapon had when it started.
    public let enchantment: ItemEnchantmentProfile?

    public init(
        damage: Float,
        reach: Float,
        speed: Float = 1,
        stagger: Float = 0,
        weapon: FormID? = nil,
        impactDataSet: FormID? = nil,
        handType: CombatHandType = .handToHand,
        enchantment: ItemEnchantmentProfile? = nil
    ) {
        self.damage = damage
        self.reach = reach
        self.speed = speed
        self.stagger = stagger
        self.weapon = weapon
        self.impactDataSet = impactDataSet
        self.handType = handType
        self.enchantment = enchantment
    }

    /// The profile of a bare-handed swing on a session with no unarmed WEAP
    /// record. One point of damage and a reach multiplier of 1, so the swing
    /// reaches exactly `fCombatDistance`.
    public static let unarmed = MeleeWeaponProfile(damage: 1, reach: 1)

    /// A hand holding a readied spell. It only carries `CombatHandType.spell` into
    /// `iRightHandType` for `magicbehavior.hkx`; that hand's button goes to the cast loop.
    public static let readiedSpell = MeleeWeaponProfile(damage: 1, reach: 1, handType: .spell)

    /// One decoded WEAP as a swing profile.
    public init(weapon record: Weapon, enchantment: ItemEnchantmentProfile? = nil) {
        self.init(
            damage: Float(record.damage),
            reach: record.reach.isFinite && record.reach > 0 ? record.reach : 1,
            speed: record.speed.isFinite && record.speed > 0 ? record.speed : 1,
            stagger: record.stagger.isFinite ? max(0, record.stagger) : 0,
            weapon: record.formID,
            impactDataSet: record.impactDataSet,
            handType: CombatHandType(weapon: record.animationType),
            enchantment: enchantment
        )
    }
}

nonisolated public enum MeleeSwing: Sendable {
    /// How far a swing reaches, in world units.
    ///
    /// A non-finite or non-positive scale is treated as 1: an actor whose scale
    /// failed to resolve must still be able to swing, and a zero reach would
    /// make every attack silently miss.
    public static func reach(
        weapon: MeleeWeaponProfile,
        settings: CombatSettings,
        actorScale: Float = 1
    ) -> Float {
        let scale = actorScale.isFinite && actorScale > 0 ? actorScale : 1
        let multiplier = weapon.reach.isFinite && weapon.reach > 0 ? weapon.reach : 1
        let base = settings.combatDistance.value
        guard base.isFinite, base > 0 else { return 0 }
        return base * scale * multiplier
    }

    /// The blade's vertical half-extent as a fraction of capsule height, centred on the
    /// chest. Our choice: it hits a target on the same floor, not one on a table.
    public static let bladeHalfExtentFraction: Float = 0.25

    /// The swing's radius, as a fraction of the attacker capsule radius.
    ///
    /// Also an OpenSky decision. The blade itself is thin, but a swing is an
    /// arc and the capsule is its hull, so the radius stands in for the arc's
    /// horizontal width rather than for the steel.
    public static let arcRadiusFraction: Float = 0.75

    /// The swing volume as a sweep query. `facing` is yaw in radians (`cos` on x, `sin` on
    /// y); `reach` comes from `reach(weapon:settings:)`.
    public static func volume(
        feet: SIMD3<Float>,
        capsule: PlayerCapsule,
        facing: Float,
        reach: Float
    ) -> ShapeSweepQuery {
        let chest = feet + SIMD3(0, 0, capsule.height * 0.5)
        let halfExtent = capsule.height * bladeHalfExtentFraction
        return ShapeSweepQuery.capsule(
            first: chest + SIMD3(0, 0, halfExtent),
            second: chest - SIMD3(0, 0, halfExtent),
            radius: capsule.radius * arcRadiusFraction,
            direction: SIMD3(cosf(facing), sinf(facing), 0),
            maximumDistance: max(reach, 0)
        )
    }
}
