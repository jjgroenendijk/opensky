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
// Documented in docs/engine/magic.md.

import Foundation
import simd

/// One enchanted weapon's hit, as the world seam receives it.
nonisolated struct WeaponEnchantmentHit: Equatable, Sendable {
    /// The weapon's resolved enchantment, fixed when the swing or the shot
    /// started.
    let profile: ItemEnchantmentProfile
    /// Who swung or shot. The charge comes off this owner's copy of the item.
    let attacker: ReferenceKey
    /// The actor that was struck.
    let target: ReferenceKey
    /// Where contact was made, world space. What an area entry measures from.
    let position: SIMD3<Float>
}

/// What applying one enchanted hit did.
nonisolated struct WeaponEnchantmentReport: Equatable, Sendable {
    let item: FormID
    /// The enchantment's display name, so a readout names it rather than a form.
    let name: String
    /// The charge after the hit. Unchanged from before it when nothing fired.
    let charge: EnchantmentCharge
    /// False when the weapon had nothing left to spend, which is the one reason
    /// a landed hit from an enchanted weapon applies nothing.
    let didFire: Bool
    /// Effect entries handed to the effect runtime.
    let entryCount: Int
    /// Timed and constant effects the runtime stored.
    let storedCount: Int
    /// Every hostile entry's resistance adjustment, in application order.
    let adjustments: [SpellMagnitudeAdjustment]

    /// One line for a readout: what fired, on what, and what is left.
    var describedLine: String {
        guard didFire else {
            return "\(name): out of charge (\(charge.describedLine))"
        }
        return "\(name): \(storedCount)/\(entryCount) effect(s) applied, \(charge.describedLine)"
    }
}

/// The seam a combat runtime applies an enchanted hit through.
///
/// One method for melee and archery both, for the reason `SpellHitApplying` is one
/// for a projectile and a target-actor cast: the two differ in how they find the
/// actor and not at all in what happens once they have one.
@MainActor
protocol WeaponEnchantmentApplying {
    /// Applies `hit`, spending the weapon's charge.
    ///
    /// - Returns: what it did, or nil when this session cannot apply enchantments
    ///   at all — every synthetic scene, which has no effect runtime.
    @discardableResult
    func applyWeaponEnchantment(_ hit: WeaponEnchantmentHit) -> WeaponEnchantmentReport?
}

/// Applying one enchanted hit to the actor it struck.
///
/// A free enum over an `inout ActiveEffectRuntime` rather than a type of its own,
/// for the reason `SpellHitApplication` is one: the effect runtime is a value over
/// a shared store whose tally advances as it works, and a copy held here would grow
/// a tally the panel never sees.
@MainActor
enum WeaponEnchantmentApplication {
    /// Spends `hit`'s charge and applies its effects to the struck actor.
    ///
    /// The charge is spent first and only once: a hit that cannot pay applies
    /// nothing, and a hit that can pay has paid even if every one of its entries
    /// turns out to be an archetype this engine does not implement. That is the
    /// order vanilla's own readout implies — the charge meter moves on the swing,
    /// not on the effect — and it is what keeps a weapon carrying an unimplemented
    /// enchantment from firing forever.
    ///
    /// - Parameters:
    ///   - owner: the actor-value holder of whoever swung, whose component holds
    ///     the charge.
    ///   - target: the struck actor's holder, or nil when it stopped being
    ///     resident between the impact and this call. The charge is still spent:
    ///     the swing landed.
    static func apply(
        _ hit: WeaponEnchantmentHit,
        owner: ActorValueHolder,
        target: ActorValueHolder?,
        using runtime: inout ActiveEffectRuntime,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> WeaponEnchantmentReport {
        let profile = hit.profile
        let ledger = EnchantmentLedger(store: runtime.store)
        guard let charge = ledger.spend(profile, on: owner) else {
            return WeaponEnchantmentReport(
                item: profile.item,
                name: profile.name,
                charge: ledger.charge(of: profile, on: owner),
                didFire: false,
                entryCount: 0,
                storedCount: 0,
                adjustments: []
            )
        }
        guard let target else {
            return WeaponEnchantmentReport(
                item: profile.item,
                name: profile.name,
                charge: charge,
                didFire: true,
                entryCount: 0,
                storedCount: 0,
                adjustments: []
            )
        }
        let scaled = SpellHitApplication.scale(
            profile.entries,
            fromPlugin: profile.sourcePlugin,
            ignoresResistance: false,
            on: target,
            using: runtime,
            resistances: resistances
        )
        let stored = runtime.apply(
            scaled.entries,
            fromPlugin: profile.sourcePlugin,
            source: profile.source,
            caster: hit.attacker,
            on: target
        )
        return WeaponEnchantmentReport(
            item: profile.item,
            name: profile.name,
            charge: charge,
            didFire: true,
            entryCount: scaled.entries.count,
            storedCount: stored.count,
            adjustments: scaled.adjustments
        )
    }
}
