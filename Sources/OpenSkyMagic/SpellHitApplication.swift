import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import simd

/// Applying one landed spell to the actors it reached.
///
/// A free function over an `inout ActiveEffectRuntime` rather than a type of its
/// own, for the reason the consumption path is one: the effect runtime is a
/// value over a shared store whose tally advances as it works, and a copy held
/// here would grow a tally the panel never sees.
@MainActor
public enum SpellHitApplication {
    /// Applies `hit` to every actor it reached, scaling hostile magnitudes by
    /// that actor's own resistances.
    ///
    /// - Parameter holders: the actor-value holder for each target key. A key
    ///   with no holder is an actor that stopped being resident between the
    ///   impact and this call, and is skipped rather than guessed at.
    @discardableResult
    public static func apply(
        _ hit: SpellHit,
        holders: [ReferenceKey: ActorValueHolder],
        using runtime: inout ActiveEffectRuntime,
        settings: MagicAreaSettings = .documentedDefaults,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> SpellHitReport {
        var report = SpellHitReport()
        for target in hit.targets {
            guard let holder = holders[target.key] else { continue }
            let reaching = entries(of: hit.payload, reaching: target, settings: settings)
            guard !reaching.isEmpty else { continue }
            let scaled = scale(
                reaching,
                of: hit.payload,
                on: holder,
                using: runtime,
                resistances: resistances
            )
            let stored = runtime.apply(
                scaled.entries,
                fromPlugin: hit.payload.sourcePlugin,
                source: hit.payload.source,
                caster: hit.payload.caster,
                on: holder
            )
            report.note(
                target: scaled.adjustments,
                entries: scaled.entries.count,
                stored: stored.count
            )
        }
        return report
    }

    /// The entries of `payload` that reach `target`.
    ///
    /// A direct target receives the whole list. A bystander receives only the
    /// entries whose authored area covers the distance between them, so one
    /// spell can damage everything in a blast while staggering only what it
    /// actually struck — which is the shape vanilla `Fireball` is authored in.
    public static func entries(
        of payload: SpellPayload,
        reaching target: SpellHitTarget,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> [MagicItemEffect] {
        entries(payload.entries, reaching: target, settings: settings)
    }

    /// The same rule for an entry list without a payload.
    public static func entries(
        _ entries: [MagicItemEffect],
        reaching target: SpellHitTarget,
        settings: MagicAreaSettings = .documentedDefaults
    ) -> [MagicItemEffect] {
        guard !target.isDirect else { return entries }
        return entries.filter { entry in
            entry.area > 0 && target.distance <= settings.radius(ofArea: entry.area)
        }
    }

    /// Scales every hostile entry by `holder`'s resistances, reporting what it
    /// moved.
    public static func scale(
        _ entries: [MagicItemEffect],
        of payload: SpellPayload,
        on holder: ActorValueHolder,
        using runtime: ActiveEffectRuntime,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> (entries: [MagicItemEffect], adjustments: [SpellMagnitudeAdjustment]) {
        scale(
            entries,
            fromPlugin: payload.sourcePlugin,
            ignoresResistance: payload.ignoresResistance,
            on: holder,
            using: runtime,
            resistances: resistances
        )
    }

    /// The same scaling without a `SpellPayload`. A weapon enchantment's contact
    /// effects pay the same resistances.
    public static func scale(
        _ entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        ignoresResistance: Bool,
        on holder: ActorValueHolder,
        using runtime: ActiveEffectRuntime,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> (entries: [MagicItemEffect], adjustments: [SpellMagnitudeAdjustment]) {
        guard !ignoresResistance else { return (entries, []) }
        var scaled: [MagicItemEffect] = []
        var adjustments: [SpellMagnitudeAdjustment] = []
        for entry in entries {
            guard
                let resolved = runtime.effects.resolve(entry, fromPlugin: pluginName),
                let data = resolved.effect.data,
                data.flags.contains(.hostile)
            else {
                scaled.append(entry)
                continue
            }
            let element = ActorValueIdentity.isVanilla(index: data.resistanceActorValue)
                ? data.resistanceActorValue
                : nil
            let multiplier = runtime.values.magicDamageMultiplier(
                element: element, on: holder, settings: resistances
            )
            adjustments.append(SpellMagnitudeAdjustment(
                target: holder.key,
                name: resolved.displayName,
                resistance: element,
                baseMagnitude: entry.magnitude,
                multiplier: multiplier
            ))
            scaled.append(entry.scalingMagnitude(by: multiplier))
        }
        return (scaled, adjustments)
    }
}
