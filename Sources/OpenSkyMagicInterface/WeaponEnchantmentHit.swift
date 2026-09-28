// An enchanted weapon landing a hit (issue #472, roadmap item 19.9): the value
// the combat runtimes hand out, the seam they hand it through, and what applying
// it does.
//
// ## Why this reuses the spell-hit machinery instead of repeating it
//
// A weapon enchantment is `Contact` delivery — the Creation Kit wiki states
// weapons "can only have 'Contact'" (<https://ck.uesp.net/wiki/Enchantment>) — and
// once an actor has been struck, a contact enchantment and a landed spell do
// exactly the same thing: scale each hostile entry by that actor's resistances and
// hand the list to the effect runtime. Item 19.8 already wrote that once, in
// `SpellHitApplication`, so this applies through it rather than beside it. The
// only thing added here is the charge: a spell pays magicka at cast time, and an
// enchantment pays charge at impact.
//
// Resistances therefore apply to a weapon enchantment. `ENIT` carries no
// "ignore resistance" flag of the kind `SPIT` has — its two documented flag bits
// are the manual-cost switch and extend-duration-on-recast — so there is no
// record-level way for an enchantment to bypass the step and none is invented.
//
// ## What a hit does not do
//
// It does not consult the enchantment's worn restriction (see
// `ItemEnchantmentProfile` for the measured reason), and it does not scale the
// charge cost by the wielder's skill (see `EnchantmentCharge`).
//
// Documented in docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One enchanted weapon's hit, as the world seam receives it.
nonisolated public struct WeaponEnchantmentHit: Equatable, Sendable {
    /// The weapon's resolved enchantment, fixed when the swing or the shot
    /// started.
    public let profile: ItemEnchantmentProfile
    /// Who swung or shot. The charge comes off this owner's copy of the item.
    public let attacker: ReferenceKey
    /// The actor that was struck.
    public let target: ReferenceKey
    /// Where contact was made, world space. What an area entry measures from.
    public let position: SIMD3<Float>

    public init(
        profile: ItemEnchantmentProfile,
        attacker: ReferenceKey,
        target: ReferenceKey,
        position: SIMD3<Float>
    ) {
        self.profile = profile
        self.attacker = attacker
        self.target = target
        self.position = position
    }
}

/// What applying one enchanted hit did.
nonisolated public struct WeaponEnchantmentReport: Equatable, Sendable {
    public let item: FormID
    /// The enchantment's display name, so a readout names it rather than a form.
    public let name: String
    /// The charge after the hit. Unchanged from before it when nothing fired.
    public let charge: EnchantmentCharge
    /// False when the weapon had nothing left to spend, which is the one reason
    /// a landed hit from an enchanted weapon applies nothing.
    public let didFire: Bool
    /// Effect entries handed to the effect runtime.
    public let entryCount: Int
    /// Timed and constant effects the runtime stored.
    public let storedCount: Int
    /// Every hostile entry's resistance adjustment, in application order.
    public let adjustments: [SpellMagnitudeAdjustment]

    /// One line for a readout: what fired, on what, and what is left.
    public var describedLine: String {
        guard didFire else {
            return "\(name): out of charge (\(charge.describedLine))"
        }
        return "\(name): \(storedCount)/\(entryCount) effect(s) applied, \(charge.describedLine)"
    }

    public init(
        item: FormID,
        name: String,
        charge: EnchantmentCharge,
        didFire: Bool,
        entryCount: Int,
        storedCount: Int,
        adjustments: [SpellMagnitudeAdjustment]
    ) {
        self.item = item
        self.name = name
        self.charge = charge
        self.didFire = didFire
        self.entryCount = entryCount
        self.storedCount = storedCount
        self.adjustments = adjustments
    }
}

/// The seam a combat runtime applies an enchanted hit through.
///
/// One method for melee and archery both, for the reason `SpellHitApplying` is one
/// for a projectile and a target-actor cast: the two differ in how they find the
/// actor and not at all in what happens once they have one.
@MainActor
public protocol WeaponEnchantmentApplying {
    /// Applies `hit`, spending the weapon's charge.
    ///
    /// - Returns: what it did, or nil when this session cannot apply enchantments
    ///   at all — every synthetic scene, which has no effect runtime.
    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport?
}
