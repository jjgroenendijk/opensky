// What can stop a landed spell before it reaches an actor: a wall between a bystander
// and the impact, a held ward, and spell absorption. Ward: "Absorbs incoming spell
// damage by subtracting the damage from itself"; absorption: "Chance to negate an
// incoming spell and grant magicka equal to its base casting cost"
// (<https://en.uesp.net/wiki/Skyrim_Mod:Actor_Value_Indices>). See
// docs/engine/spell-delivery.md#defences.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// The world answers a defence needs. Every default lets the spell through.
@MainActor
public struct SpellHitDefences {
    /// A roll in 0 ..< 100 for the absorption chance.
    public var absorptionRoll: () -> Float = { 100 }
    /// Whether `target` faces the caster closely enough for its ward to block.
    public var wardFaces: (_ target: ReferenceKey, _ caster: ReferenceKey) -> Bool = { _, _ in
        true
    }

    /// Whether nothing solid stands between `impact` and the bystander.
    public var reaches: (_ target: ReferenceKey, _ impact: SIMD3<Float>) -> Bool = { _, _ in true }
    /// The `Mod Ward Magicka Absorption Pct` share a ward holder gets back.
    public var wardMagickaShare: (_ holder: ReferenceKey) -> Float = { _ in 0 }

    public static let none = SpellHitDefences()

    public init() {}

    /// Runs the defences for one target, changing its actor values as they act.
    /// `entries` are the ones that reach the target, before resistance.
    func defend(
        _ target: SpellHitTarget,
        holder: ActorValueHolder,
        entries: [MagicItemEffect],
        hit: SpellHit,
        runtime: ActiveEffectRuntime
    ) -> SpellDefenceOutcome {
        let payload = hit.payload
        if
            !target.isDirect, !payload.areaIgnoresLineOfSight, let impact = hit.impact,
            !reaches(target.key, impact)
        {
            return .blockedByWall
        }
        let values = runtime.values
        let ward = values.value(at: SpellHitApplication.wardPowerActorValue, on: holder) ?? 0
        // UESP: "self-applying spells ... will not be absorbed".
        guard payload.isHostile, payload.caster != target.key else {
            return ward > 0 && payload.caster != target.key ? .landsThroughWard : .lands
        }
        if ward > 0, wardFaces(target.key, payload.caster) {
            let damage = SpellHitApplication.hostileMagnitude(
                of: entries, fromPlugin: payload.sourcePlugin, runtime
            )
            let taken = min(ward, damage)
            values.damage(at: SpellHitApplication.wardPowerActorValue, by: taken, on: holder)
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
    public static let absorbChanceActorValue: Int32 = 83
    public static let magickaActorValue: Int32 = 25

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
