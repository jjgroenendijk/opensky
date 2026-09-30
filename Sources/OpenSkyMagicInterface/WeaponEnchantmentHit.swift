// An enchanted weapon landing a hit: the value the combat runtimes hand out,
// the seam, and what applying it does. A contact enchantment applies through
// `SpellHitApplication`, resistances included, and pays charge at impact. It
// does not check the worn restriction or scale the charge by skill.
// See docs/engine/item-enchantments.md.

import Foundation
import OpenSkyFormatsESM
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

    public init(
        profile: ItemEnchantmentProfile,
        attacker: ReferenceKey,
        target: ReferenceKey
    ) {
        self.profile = profile
        self.attacker = attacker
        self.target = target
    }
}

/// What applying one enchanted hit did.
nonisolated public struct WeaponEnchantmentReport: Equatable, Sendable {
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
        name: String,
        charge: EnchantmentCharge,
        didFire: Bool,
        entryCount: Int,
        storedCount: Int,
        adjustments: [SpellMagnitudeAdjustment]
    ) {
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
