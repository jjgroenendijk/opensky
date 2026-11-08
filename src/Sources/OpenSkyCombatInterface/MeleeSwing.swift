public import OpenSkyActorsInterface
public import OpenSkyFormatsESM
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
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
    /// WEAP DATA carry weight, which sets a power attack's stamina cost.
    public let weight: Float

    public init(
        damage: Float,
        reach: Float,
        speed: Float = 1,
        stagger: Float = 0,
        weapon: FormID? = nil,
        impactDataSet: FormID? = nil,
        handType: CombatHandType = .handToHand,
        enchantment: ItemEnchantmentProfile? = nil,
        weight: Float = 0
    ) {
        self.damage = damage
        self.reach = reach
        self.speed = speed
        self.stagger = stagger
        self.weapon = weapon
        self.impactDataSet = impactDataSet
        self.handType = handType
        self.enchantment = enchantment
        self.weight = weight
    }

    /// The profile of a bare-handed swing on a session with no unarmed WEAP
    /// record. One point of damage and a reach multiplier of 1, so the swing
    /// reaches exactly `fCombatDistance`.
    public static let unarmed = MeleeWeaponProfile(damage: 1, reach: 1)

    /// A hand holding a readied spell. It only carries `CombatHandType.spell` into
    /// `iRightHandType` for `magicbehavior.hkx`; that hand's button goes to the cast loop.
    public static let readiedSpell = MeleeWeaponProfile(damage: 1, reach: 1, handType: .spell)

    /// This profile with the tempering bonus of a copy at `level` added.
    public func tempered(level: Int32) -> MeleeWeaponProfile {
        dealing(damage: damage + Tempering.bonus(level: level, isBodyArmor: false))
    }

    /// This profile dealing `damage` instead of its own, for tempering and a bash.
    public func dealing(damage: Float) -> MeleeWeaponProfile {
        MeleeWeaponProfile(
            damage: damage,
            reach: reach,
            speed: speed,
            stagger: stagger,
            weapon: weapon,
            impactDataSet: impactDataSet,
            handType: handType,
            enchantment: enchantment,
            weight: weight
        )
    }

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
            enchantment: enchantment,
            weight: record.itemValue.weight.isFinite ? max(0, record.itemValue.weight) : 0
        )
    }
}
