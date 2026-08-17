// The shape a swing occupies and the reach that sizes it (issue #195, roadmap
// item 15.4).
//
// Reach comes straight from the documented combat-distance formula:
//
//     reach = fCombatDistance * actorScale * WEAP.reach
//
// UESP "Skyrim Mod:Mod File Format/WEAP" describes DNAM `reach` as exactly
// that multiplier, and xEdit's `wbDefinitionsTES5.pas` names the same DNAM
// member at the same offset (both citations are already carried on
// `Weapon.swift`, where the field is decoded). Nothing here is measured, so
// nothing here needs a measurement recorded: the formula is documented and the
// two inputs are read rather than estimated. What OpenSky does supply is the
// unarmed fallback — a WEAP-less swing has no `reach` to multiply, and vanilla
// resolves that through the unarmed pseudo-weapon record, so a session without
// one falls back to a bare `fCombatDistance` and says so.
//
// The swing volume is a `ShapeSweepQuery` (item 15.2), which is what the issue
// asks for and is also the honest shape: a swing is a blade segment travelling
// along an arc, and a swept capsule is the conservative hull of that segment
// over the part of the arc that can connect. Conservative in the same direction
// 15.2's sweeps already are — a hit may register marginally early, never late.
//
// The arc is *not* reconstructed from the animation pose. The weapon bone's
// world transform is available, but a hit resolved from one sampled frame of a
// 30 Hz clip lands wherever that frame happened to be, and the vanilla contact
// frame is a single annotation rather than a window. So the volume is built
// from the attacker's facing at the contact frame, which is what the player
// aimed, and the blade segment gives it the vertical extent a point query would
// miss.
//
// Documented in docs/engine/melee-combat.md.

import simd

/// Everything a swing needs to know about the weapon making it.
nonisolated struct MeleeWeaponProfile: Equatable, Sendable {
    /// WEAP DATA base damage.
    let damage: Float
    /// WEAP DNAM `reach` multiplier.
    let reach: Float
    /// WEAP DNAM `speed`, written to `weaponSpeedMult`.
    let speed: Float
    /// WEAP DNAM `stagger` magnitude, written to `staggerMagnitude` on the
    /// target's graph.
    let stagger: Float
    /// The WEAP itself, for the readout and the impact-data lookup. Nil for an
    /// unarmed swing.
    let weapon: FormID?
    /// BIDS — the impact data set the hit resolves its sound through.
    let impactDataSet: FormID?
    /// Which animation set the graph plays for this weapon, written to
    /// `iRightHandType` (issue #403).
    let handType: CombatHandType
    /// The weapon's resolved enchantment, or nil when it carries none (issue
    /// #472).
    ///
    /// Resolved when equipment resolves and carried with the profile rather than
    /// looked up at the contact frame, for the reason `ArrowPayload` fixes its
    /// damage at launch: a swing must apply the enchantment the weapon had when it
    /// started, not whatever the player has equipped by the time it lands.
    let enchantment: ItemEnchantmentProfile?

    init(
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
    static let unarmed = MeleeWeaponProfile(damage: 1, reach: 1)

    /// The profile of a hand holding a readied spell (issue #470).
    ///
    /// Its only job is to carry `CombatHandType.spell` into `iRightHandType`,
    /// which is the value `magicbehavior.hkx` reads. The damage and reach are
    /// the unarmed ones and are never used: `MeleeCombatRuntime` never gets an
    /// attack event for a hand holding a spell, because that hand's button goes
    /// to the cast loop instead.
    static let readiedSpell = MeleeWeaponProfile(damage: 1, reach: 1, handType: .spell)

    /// One decoded WEAP as a swing profile.
    init(weapon record: Weapon, enchantment: ItemEnchantmentProfile? = nil) {
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

nonisolated enum MeleeSwing {
    /// How far a swing reaches, in world units.
    ///
    /// A non-finite or non-positive scale is treated as 1: an actor whose scale
    /// failed to resolve must still be able to swing, and a zero reach would
    /// make every attack silently miss.
    static func reach(
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

    /// The blade's vertical half-extent, as a fraction of the attacker capsule
    /// height, centred on the chest.
    ///
    /// An **OpenSky decision**, not a documented number: vanilla's hit volume
    /// lives in its own code and is not readable from the install. Half a
    /// capsule height about the chest covers a target standing on the same
    /// floor without reaching one standing on a table, which is the behaviour a
    /// player expects from a horizontal swing.
    static let bladeHalfExtentFraction: Float = 0.25

    /// The swing's radius, as a fraction of the attacker capsule radius.
    ///
    /// Also an OpenSky decision. The blade itself is thin, but a swing is an
    /// arc and the capsule is its hull, so the radius stands in for the arc's
    /// horizontal width rather than for the steel.
    static let arcRadiusFraction: Float = 0.75

    /// The volume a swing occupies, as a 15.2 sweep query.
    ///
    /// - Parameters:
    ///   - feet: the attacker's capsule bottom, world space.
    ///   - capsule: the attacker's capsule dimensions.
    ///   - facing: yaw the attacker is facing, radians, matching the
    ///     locomotion bridge's convention (`cos` forward on x, `sin` on y).
    ///   - reach: how far the swing travels, from `reach(weapon:settings:)`.
    static func volume(
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
