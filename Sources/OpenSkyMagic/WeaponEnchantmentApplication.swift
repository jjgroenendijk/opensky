import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import simd

/// Applying one enchanted hit to the actors it reached.
///
/// A free enum over an `inout ActiveEffectRuntime` rather than a type of its own,
/// for the reason `SpellHitApplication` is one: the effect runtime is a value over
/// a shared store whose tally advances as it works, and a copy held here would grow
/// a tally the readout never sees.
@MainActor
public enum WeaponEnchantmentApplication {
    /// Spends `hit`'s charge once, then applies its effects to every actor it reached.
    /// - Parameters:
    ///   - owner: whoever swung, whose weapon copy holds the charge. A trap is nil: it
    ///     holds no copy, so its charge never runs out.
    ///   - holders: each target's holder. A target with none is no longer resident.
    public static func apply(
        _ hit: WeaponEnchantmentHit,
        owner: ActorValueHolder?,
        holders: [ReferenceKey: ActorValueHolder],
        using runtime: inout ActiveEffectRuntime,
        settings: MagicAreaSettings = .documentedDefaults,
        resistances: ActorResistanceSettings = .documentedDefaults,
        inventory: (any InventoryAccess)? = nil
    ) -> WeaponEnchantmentReport {
        let profile = hit.profile
        let ledger = EnchantmentLedger(store: runtime.store, inventory: inventory)
        let charge: EnchantmentCharge
        if let owner {
            guard let spent = ledger.spend(profile, on: owner) else {
                return unfired(profile, charge: ledger.charge(of: profile, on: owner))
            }
            charge = spent
        } else {
            charge = EnchantmentCharge(capacity: profile.capacity, costPerUse: 0)
        }
        var tally = SpellHitReport()
        for target in hit.targets {
            guard let holder = holders[target.key] else { continue }
            let reaching = SpellHitApplication.entries(
                profile.entries, reaching: target, settings: settings
            )
            guard !reaching.isEmpty else { continue }
            let scaled = SpellHitApplication.scale(
                reaching,
                fromPlugin: profile.sourcePlugin,
                ignoresResistance: false,
                on: holder,
                using: runtime,
                resistances: resistances
            )
            let stored = runtime.apply(
                scaled.entries,
                fromPlugin: profile.sourcePlugin,
                source: profile.source,
                caster: hit.attacker,
                on: holder
            )
            tally.note(
                target: scaled.adjustments,
                entries: scaled.entries.count,
                stored: stored.count
            )
        }
        return WeaponEnchantmentReport(
            name: profile.name,
            charge: charge,
            didFire: true,
            entryCount: tally.entryCount,
            storedCount: tally.storedCount,
            adjustments: tally.adjustments
        )
    }

    private static func unfired(
        _ profile: ItemEnchantmentProfile, charge: EnchantmentCharge
    ) -> WeaponEnchantmentReport {
        WeaponEnchantmentReport(
            name: profile.name, charge: charge, didFire: false,
            entryCount: 0, storedCount: 0, adjustments: []
        )
    }

    /// Applies a hit that reached only `target`, or nothing when it is nil.
    public static func apply(
        _ hit: WeaponEnchantmentHit,
        owner: ActorValueHolder?,
        target: ActorValueHolder?,
        using runtime: inout ActiveEffectRuntime,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> WeaponEnchantmentReport {
        apply(
            hit,
            owner: owner,
            holders: target.map { [$0.key: $0] } ?? [:],
            using: &runtime,
            resistances: resistances
        )
    }
}
