import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import simd

/// Applying one enchanted hit to the actor it struck.
///
/// A free enum over an `inout ActiveEffectRuntime` rather than a type of its own,
/// for the reason `SpellHitApplication` is one: the effect runtime is a value over
/// a shared store whose tally advances as it works, and a copy held here would grow
/// a tally the panel never sees.
@MainActor
public enum WeaponEnchantmentApplication {
    /// Spends `hit`'s charge and applies its effects to the struck actor. The charge
    /// is spent first and once, even when no entry is implemented.
    /// - Parameters:
    ///   - owner: the holder of whoever swung, whose component holds the charge.
    ///   - target: the struck actor's holder, or nil when it stopped being resident.
    ///     The charge is still spent.
    public static func apply(
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
            name: profile.name,
            charge: charge,
            didFire: true,
            entryCount: scaled.entries.count,
            storedCount: stored.count,
            adjustments: scaled.adjustments
        )
    }
}
