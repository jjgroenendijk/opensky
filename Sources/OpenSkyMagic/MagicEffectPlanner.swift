// Archetype dispatch: one decoded MGEF plus its EFIT numbers becomes what the
// runtime does. Pure. Each archetype's rule is `MagicArchetypeRule`, from
// <https://ck.uesp.net/wiki/Magic_Effect>. The Detrimental flag sets direction.
// No Magnitude and No Duration are ignored, as the wiki says they change only
// the editor. See docs/engine/magic.md and docs/engine/magic-archetypes.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// One MGEF entry resolved into an application the runtime can carry out.
nonisolated public struct MagicEffectApplication: Equatable, Sendable {
    /// The MGEF being applied.
    public let effect: ReferenceKey
    public let archetype: MagicEffectArchetype
    /// Nil for an effect that only carries a perk.
    public let rule: MagicArchetypeRule?
    /// Which of the two documented timed behaviours applies. Meaningless for an
    /// instant application, which is applied once and stored nowhere.
    public let mode: ActiveEffectMode
    public let isDetrimental: Bool
    /// EFIT duration in seconds; zero for an instantaneous effect.
    public let duration: Float
    /// The actor values acted on, first value first. An archetype that acts on
    /// no actor value carries one value at `noneIndex` holding the magnitude.
    public let values: [ActiveEffectValue]
    /// Peak Value Modifier's second associated item.
    public let stackKeyword: ReferenceKey?
    /// The EFIT area, feet. Detect Life reads its range here.
    public var area: UInt32 = 0
    /// MGEF No Recast: "Once the magic effect is applied to a target, it cannot
    /// be cast again on the same target until it has worn off or been
    /// dispelled."
    public let refusesRecast: Bool

    /// Whether the effect applies once rather than persisting. A constant effect also
    /// has zero duration but persists, so the mode is checked first.
    public var isInstant: Bool {
        mode != .constant && duration <= 0
    }

    /// The EFIT magnitude, which a level cap or a cloak radius reads.
    public var magnitude: Float {
        values.first?.magnitude ?? 0
    }
}

/// Why one effect entry produced no application. Every case is a tally bucket,
/// never an error: a potion with one unimplemented effect still applies its
/// other ones.
/// The `Error` conformance exists only so these can ride in a `Result`; nothing
/// here ever throws one, exactly as `ConditionFailure` documents.
nonisolated public enum MagicEffectPlanFailure: Equatable, Error, Hashable, Sendable {
    /// The archetype has no implementation yet.
    case unimplementedArchetype(MagicEffectArchetype)
    /// The archetype is implemented but the record names no actor value inside
    /// the vanilla table — usually -1, "none".
    case unaddressableValue(Int32)
    /// The MGEF carried no readable DATA, so nothing about it is known.
    case undecodedEffect
    /// The archetype only acts while it runs, and the entry has no duration.
    case needsDuration(MagicEffectArchetype)
    /// Paralysis "only works if the 'Recover' flag is set".
    case needsRecover(MagicEffectArchetype)
    /// The target's level is above the magnitude: "up to level <MAG>".
    case aboveLevelCap(MagicEffectArchetype)
    /// Turn Undead "is hard-coded to require that the target have the
    /// ActorTypeUndead keyword".
    case notUndead
    /// Enhance Weapon found no melee weapon in the target's hands.
    case noMeleeWeapon
    /// Enhance Weapon found the weapon already enchanted or conjured.
    case weaponEnchanted
    /// Banish, Command Summoned, and Werewolf Feed act on a summon or a corpse only.
    case wrongTarget(MagicEffectArchetype)
}

nonisolated public enum MagicEffectPlanner: Sendable {
    public enum Outcome: Equatable, Sendable {
        case apply(MagicEffectApplication)
        case skip(MagicEffectPlanFailure)
    }

    /// Whether `archetype` has a rule. Everything else is counted and applies
    /// nothing.
    public static func implements(_ archetype: MagicEffectArchetype) -> Bool {
        MagicArchetypeRule.rule(for: archetype) != nil
    }

    /// Whether a planned effect does anything. An effect that applies a perk must
    /// exist to own it, even when its values mean nothing to this engine.
    public static func applies(_ data: MagicEffectData) -> Bool {
        implements(data.archetype) || data.perkToApply != nil
    }

    /// Plans one EFID/EFIT/CTDA `entry` of the resolved MGEF `effect`.
    /// `isConstant` marks a worn enchantment, whose zero duration means "while
    /// worn". `resolveKeyword` turns the plugin-relative keyword link into a key,
    /// so the planner stays pure.
    public static func plan(
        effect: ResolvedMagicEffect,
        entry: MagicItemEffect,
        isConstant: Bool = false,
        valueAndParts: MagicValueAndPartsScale = MagicValueAndPartsScale(),
        resolveKeyword: (FormID) -> ReferenceKey? = { _ in nil }
    ) -> Outcome {
        guard let data = effect.effect.data else {
            return .skip(.undecodedEffect)
        }
        guard applies(data) else {
            return .skip(.unimplementedArchetype(data.archetype))
        }
        let rule = MagicArchetypeRule.rule(for: data.archetype)
        let duration = isConstant ? 0 : Float(entry.duration)
        if let reason = refusal(of: rule, data: data, duration: duration, isConstant: isConstant) {
            return .skip(reason)
        }
        let planned = rule.map {
            values(of: $0, data: data, magnitude: entry.magnitude, scale: valueAndParts)
        } ?? .success([])
        let values: [ActiveEffectValue]
        switch planned {
        case let .success(planned):
            values = planned
        case let .failure(reason) where data.perkToApply == nil:
            return .skip(reason)
        case .failure:
            values = []
        }
        // A timed Recover effect on health, magicka, or stamina applies like any held
        // modifier: a primary's temporary slot moves its maximum and the current value.
        // Expiry's floor is `ActiveEffectRuntime.release`.
        var application = MagicEffectApplication(
            effect: ReferenceKey(resolved: effect.id),
            archetype: data.archetype,
            rule: rule,
            mode: mode(of: rule, flags: data.flags, isConstant: isConstant),
            isDetrimental: rule.map { isDetrimental($0, flags: data.flags) }
                ?? data.flags.contains(.detrimental),
            duration: duration,
            values: values,
            stackKeyword: data.archetype == .peakValueModifier
                ? data.associatedItem.flatMap(resolveKeyword)
                : nil,
            refusesRecast: data.flags.contains(.noRecast)
        )
        application.area = entry.area
        return .apply(application)
    }

    // MARK: - Private

    private static func refusal(
        of rule: MagicArchetypeRule?,
        data: MagicEffectData,
        duration: Float,
        isConstant: Bool
    ) -> MagicEffectPlanFailure? {
        guard let rule else { return nil }
        if rule.needsDuration, !isConstant, duration <= 0 {
            return .needsDuration(data.archetype)
        }
        if rule == .influence(.paralysis), !data.flags.contains(.recover) {
            return .needsRecover(data.archetype)
        }
        return nil
    }

    /// A held flag, paralysis, and a growing value hold their slot whatever the
    /// Recover flag says; Absorb pays out each second, because it moves health
    /// between two actors and a held slot cannot.
    private static func mode(
        of rule: MagicArchetypeRule?,
        flags: MagicEffectFlags,
        isConstant: Bool
    ) -> ActiveEffectMode {
        if isConstant {
            return .constant
        }
        switch rule {
        case .heldFlag, .influence(.paralysis), .accumulate, .world(.enhanceWeapon):
            return .modifier
        case .absorb: return .perSecond
        default: return flags.contains(.recover) ? .modifier : .perSecond
        }
    }

    /// A flag is set to 1, never taken to -1, whatever the Detrimental flag says.
    private static func isDetrimental(_ rule: MagicArchetypeRule, flags: MagicEffectFlags) -> Bool {
        switch rule {
        case .heldFlag, .influence(.paralysis), .accumulate: false
        default: flags.contains(.detrimental)
        }
    }

    /// The actor values one rule acts on, or why it acts on none.
    private static func values(
        of rule: MagicArchetypeRule,
        data: MagicEffectData,
        magnitude: Float,
        scale: MagicValueAndPartsScale
    ) -> Result<[ActiveEffectValue], MagicEffectPlanFailure> {
        switch rule {
        case let .heldFlag(index):
            .success([ActiveEffectValue(index: index, magnitude: 1)])
        case .influence(.paralysis):
            .success([
                ActiveEffectValue(index: MagicArchetypeRule.paralysisActorValue, magnitude: 1)
            ])
        case .actorValues, .absorb, .accumulate:
            actorValues(of: data, magnitude: magnitude)
        case .valueAndParts:
            actorValues(of: data, magnitude: magnitude * scale.value).map { values in
                values + MagicArchetypeRule.bodyPartConditionValues.map {
                    ActiveEffectValue(index: $0, magnitude: magnitude * scale.parts)
                }
            }
        case .world(.enhanceWeapon)
            where ActorValueIdentity.isVanilla(index: data.relatedActorValue):
            actorValues(of: data, magnitude: magnitude)
        case .influence, .dispel, .carrier, .world:
            .success([
                ActiveEffectValue(index: ActorValueIdentity.noneIndex, magnitude: magnitude)
            ])
        }
    }

    private static func actorValues(
        of data: MagicEffectData,
        magnitude: Float
    ) -> Result<[ActiveEffectValue], MagicEffectPlanFailure> {
        let primary = data.relatedActorValue
        guard ActorValueIdentity.isVanilla(index: primary) else {
            return .failure(.unaddressableValue(primary))
        }
        var values = [ActiveEffectValue(index: primary, magnitude: magnitude)]
        guard data.archetype == .dualValueModifier else {
            return .success(values)
        }
        // The second value is optional even on a dual modifier: xEdit's own
        // definition allows -1 there, and an effect that names only one value
        // is still a working single-value modifier rather than a broken record.
        let second = data.secondActorValue
        guard ActorValueIdentity.isVanilla(index: second) else {
            return .success(values)
        }
        let weight = data.secondActorValueWeight.isFinite ? data.secondActorValueWeight : 0
        values.append(ActiveEffectValue(index: second, magnitude: magnitude * weight))
        return .success(values)
    }
}
