import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import simd

/// Applying one enchanted hit to the actors it reached.
///
/// A free enum over an `inout ActiveEffectRuntime` rather than a type of its own,
/// for the reason `SpellHitApplication` is one: the effect runtime is a value over
/// a shared store whose tally advances as it works, and a copy held here would grow
/// a tally the panel never sees.
@MainActor
public enum WeaponEnchantmentApplication {
    /// Spends `hit`'s charge and applies its effects to every actor it reached. The
    /// charge is spent first and once, even when no entry is implemented.
    /// - Parameters:
    ///   - owner: the holder of whoever swung, whose component holds the charge.
    ///   - holders: the holder of each target. A target with no holder stopped
    ///     being resident and is skipped. The charge is still spent.
    public static func apply(
        _ hit: WeaponEnchantmentHit,
        owner: ActorValueHolder,
        holders: [ReferenceKey: ActorValueHolder],
        using runtime: inout ActiveEffectRuntime,
        settings: MagicAreaSettings = .documentedDefaults,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> WeaponEnchantmentReport {
        let profile = hit.profile
        let ledger = EnchantmentLedger(store: runtime.store)
        guard let charge = ledger.spend(profile, on: owner) else {
            return WeaponEnchantmentReport(
                name: profile.name,
                charge: ledger.charge(of: profile, on: owner),
                didFire: false,
                entryCount: 0,
                storedCount: 0,
                adjustments: []
            )
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

    /// Applies a hit that reached only `target`, or nothing when it is nil.
    public static func apply(
        _ hit: WeaponEnchantmentHit,
        owner: ActorValueHolder,
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
