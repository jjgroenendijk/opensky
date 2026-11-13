import Foundation
import OpenSkyActorsInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
import simd

/// Applying one landed spell to the actors it reached.
///
/// A free function over an `inout ActiveEffectRuntime` rather than a type of its
/// own, for the reason the consumption path is one: the effect runtime is a
/// value over a shared store whose tally advances as it works, and a copy held
/// here would grow a tally the readout never sees.
@MainActor
public enum SpellHitApplication {
    /// Applies `hit` to every actor it reached, scaling each entry by `perkScaling` and
    /// hostile magnitudes by that actor's own resistances.
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
        resistances: ActorResistanceSettings = .documentedDefaults,
        defences: SpellHitDefences = .none,
        perkScaling: ([MagicItemEffect], ReferenceKey) -> [MagicItemEffect] = { entries, _ in
            entries
        }
    ) -> SpellHitReport {
        var report = SpellHitReport()
        for target in hit.targets {
            guard let holder = holders[target.key] else { continue }
            let reaching = perkScaling(
                entries(of: hit.payload, reaching: target, settings: settings), target.key
            )
            guard !reaching.isEmpty else { continue }
            switch defences.defend(
                (target, holder), entries: reaching, hit: hit, runtime: runtime
            ) {
            case .lands: break
            case .landsThroughWard: report.noteFriendlyWardHit(target.key)
            case .blockedByWall:
                report.noteBlockedByWall()
                continue
            case .absorbed:
                report.noteAbsorbed()
                continue
            case let .warded(_, broken, _):
                report.noteWarded(target.key, broken: broken)
                continue
            }
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
            let tally = runtime.lastApplication
            if tally.refused > 0 {
                report.noteRefusal(SpellTargetRefusal(
                    target: target.key, aboveLevelCap: tally.aboveLevelCap,
                    nothingLanded: tally.landed == 0
                ))
            }
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
            source: (payload.sourcePlugin, payload.ignoresResistance),
            on: holder,
            using: runtime,
            resistances: resistances
        )
    }

    /// The same scaling without a `SpellPayload`. A weapon enchantment's contact
    /// effects pay the same resistances.
    public static func scale(
        _ entries: [MagicItemEffect],
        source: (plugin: String, ignoresResistance: Bool),
        on holder: ActorValueHolder,
        using runtime: ActiveEffectRuntime,
        resistances: ActorResistanceSettings = .documentedDefaults
    ) -> (entries: [MagicItemEffect], adjustments: [SpellMagnitudeAdjustment]) {
        let (pluginName, ignoresResistance) = source
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

/// What can stop a landed spell before it reaches an actor: a wall, a held ward, or
/// spell absorption (docs/engine/spell-delivery.md#defences). Every default lets the
/// spell through.
@MainActor
public struct SpellHitDefences {
    /// A roll in 0 ..< 100 for the absorption chance.
    var absorptionRoll: () -> Float = { 100 }
    /// Whether `target` faces the caster closely enough for its ward to block.
    var wardFaces: (_ target: ReferenceKey, _ caster: ReferenceKey) -> Bool = { _, _ in
        true
    }

    /// Whether nothing solid stands between `impact` and the bystander.
    var reaches: (_ target: ReferenceKey, _ impact: SIMD3<Float>) -> Bool = { _, _ in true }
    /// The `Mod Ward Magicka Absorption Pct` share a ward holder gets back.
    var wardMagickaShare: (_ holder: ReferenceKey) -> Float = { _ in 0 }
    /// The most ward power `holder` may hold (`MagicWorldSettings.wardPowerCap`).
    var wardPowerCap: (_ holder: ActorValueHolder) -> Float = { _ in .infinity }

    public static let none = SpellHitDefences()

    public init() {}

    /// Runs the defences for one target, changing its actor values as they act.
    /// `entries` are the ones that reach the target, before resistance.
    func defend(
        _ struck: (target: SpellHitTarget, holder: ActorValueHolder),
        entries: [MagicItemEffect],
        hit: SpellHit,
        runtime: ActiveEffectRuntime
    ) -> SpellDefenceOutcome {
        let (target, holder) = struck
        let payload = hit.payload
        if
            !target.isDirect, !payload.areaIgnoresLineOfSight, let impact = hit.impact,
            !reaches(target.key, impact)
        {
            return .blockedByWall
        }
        let values = runtime.values
        let held = values.value(at: SpellHitApplication.wardPowerActorValue, on: holder) ?? 0
        let ward = min(held, wardPowerCap(holder))
        // UESP: "self-applying spells ... will not be absorbed".
        guard payload.isHostile, payload.caster != target.key else {
            return ward > 0 && payload.caster != target.key ? .landsThroughWard : .lands
        }
        if ward > 0, wardFaces(target.key, payload.caster) {
            let damage = SpellHitApplication.hostileMagnitude(
                of: entries, fromPlugin: payload.sourcePlugin, runtime
            )
            let taken = min(ward, damage)
            // Power above the cap never blocks, so a capped ward breaks with it gone.
            let spent = damage > ward ? held : taken
            values.damage(at: SpellHitApplication.wardPowerActorValue, by: spent, on: holder)
            let magicka = taken * max(0, wardMagickaShare(target.key))
            if magicka > 0 {
                values.restore(at: SpellHitApplication.magickaActorValue, by: magicka, on: holder)
            }
            return .warded(damage: taken, broken: damage > ward, magicka: magicka)
        }
        let chance = values.value(at: SpellHitApplication.absorbChanceActorValue, on: holder) ?? 0
        guard !payload.disallowsAbsorb, chance > 0, absorptionRoll() < chance else {
            return .lands
        }
        values.restore(at: SpellHitApplication.magickaActorValue, by: payload.baseCost, on: holder)
        return .absorbed(magicka: payload.baseCost)
    }
}

/// How a defence answered one target.
nonisolated public enum SpellDefenceOutcome: Equatable, Sendable {
    case lands
    /// A spell that is not hostile passed through the target's ward.
    case landsThroughWard
    case blockedByWall
    case absorbed(magicka: Float)
    /// A ward took `damage`. A broken ward still blocks the spell.
    case warded(damage: Float, broken: Bool, magicka: Float)
}

extension SpellHitApplication {
    /// Ward Power, which a ward effect accumulates while held.
    public static let wardPowerActorValue: Int32 = 63
    /// Absorb Chance, in percent.
    static let absorbChanceActorValue: Int32 = 83
    static let magickaActorValue: Int32 = 25

    /// The summed magnitude of the hostile entries, which is what a ward has to hold.
    static func hostileMagnitude(
        of entries: [MagicItemEffect],
        fromPlugin pluginName: String,
        _ runtime: ActiveEffectRuntime
    ) -> Float {
        entries.reduce(0) { total, entry in
            let hostile = runtime.effects.resolve(entry, fromPlugin: pluginName)?
                .effect.data?.flags.contains(.hostile) == true
            return total + (hostile ? max(0, entry.magnitude) : 0)
        }
    }
}
