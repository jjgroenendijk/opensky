// Archetype dispatch (issue #469, roadmap item 19.6): turning one decoded MGEF
// plus the EFIT numbers beside it into what the runtime should actually do.
//
// A pure function over decoded records, deliberately separate from
// `ActiveEffectRuntime`: everything here is testable with no store, no actor
// and no world, and the runtime below it never has to reason about a flag bit.
//
// ## The archetypes this item implements, and their cited semantics
//
// From the Creation Kit wiki's Magic Effect page, Effect Archetypes table
// (<https://ck.uesp.net/wiki/Magic_Effect>, read through the Wayback Machine —
// see docs/tools/environment.md on why the live host is unreachable):
//
//   Value Modifier — "1. The value to modify. ... Modifies the Actor Value by
//   <MAG>."
//   Dual Value Modifier — "1: The first value 2: The second value ... Modifies
//   both Actor Values. The first value is modified by <MAG>, the second value
//   is modified by <MAG> * AV Weight."
//   Peak Value Modifier — "1: The value to modify. 2: A keyword for effects it
//   does not stack with. If there are two PVMs with the same keyword active at
//   the same time, the one with the lower <mag> will be dispelled
//   automatically?"
//
// The question mark is the wiki's own; the rule is implemented as written and
// the uncertainty is recorded in docs/engine/magic.md rather than hidden.
//
// Every other archetype applies nothing and is counted, so the unimplemented
// ground is measured rather than silent.
//
// ## Which actor value, and which direction
//
// UESP's MGEF DATA table names `44:PrimaryAV` and `58:SecondAV` as actor-value
// indices with -1 for none
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/MGEF>), which the
// decoder calls `relatedActorValue` and `secondActorValue`. Direction is the
// Detrimental flag: "This Effect is applied as a negative value (damage) to the
// specified Actor Value."
//
// ## Why the No Magnitude / No Duration flags are ignored here
//
// The same Creation Kit page states it outright: "No Magnitude, No Area and No
// Duration do not actually affect the inner workings of the effect, checking
// them just makes it so these parameters will be unavailable when you assign
// the effect". The EFIT numbers are therefore taken as authored.
//
// Documented in docs/engine/magic.md.

import Foundation

/// One MGEF entry resolved into an application the runtime can carry out.
nonisolated struct MagicEffectApplication: Equatable {
    /// The MGEF being applied.
    let effect: ReferenceKey
    let archetype: MagicEffectArchetype
    /// Which of the two documented timed behaviours applies. Meaningless for an
    /// instant application, which is applied once and stored nowhere.
    let mode: ActiveEffectMode
    let isDetrimental: Bool
    /// EFIT duration in seconds; zero for an instantaneous effect.
    let duration: Float
    /// The actor values acted on, first value first.
    let values: [ActiveEffectValue]
    /// Peak Value Modifier's second associated item.
    let stackKeyword: ReferenceKey?
    /// MGEF No Recast: "Once the magic effect is applied to a target, it cannot
    /// be cast again on the same target until it has worn off or been
    /// dispelled."
    let refusesRecast: Bool

    /// Whether the effect applies once rather than persisting.
    ///
    /// A constant effect also carries a duration of zero and is the opposite of
    /// instant: it persists until the item that granted it comes off, so the
    /// mode is asked before the number (issue #472).
    var isInstant: Bool {
        mode != .constant && duration <= 0
    }
}

/// Why one effect entry produced no application. Every case is a tally bucket,
/// never an error: a potion with one unimplemented effect still applies its
/// other ones.
/// The `Error` conformance exists only so these can ride in a `Result`; nothing
/// here ever throws one, exactly as `ConditionFailure` documents.
nonisolated enum MagicEffectPlanFailure: Equatable, Error, Hashable, Sendable {
    /// The archetype has no implementation in this milestone.
    case unimplementedArchetype(MagicEffectArchetype)
    /// The archetype is implemented but the record names no actor value inside
    /// the vanilla table — usually -1, "none".
    case unaddressableValue(Int32)
    /// A timed Recover effect naming health, magicka or stamina.
    ///
    /// The Creation Kit documents this as changing both the maximum and the
    /// current value. Item 19.5 left the three primaries without the storage to
    /// hold that, so such an effect was counted rather than approximated —
    /// moving current health for a "fortify health" effect would be a different
    /// effect wearing the same name.
    ///
    /// Item 20.3 (issue #496) built the storage, so the reason no longer holds.
    /// The guard stays until the tallies it moves are re-measured against the
    /// install and the expiry path is exercised deliberately: issue #511.
    case unsupportedPrimaryModifier(Int32)
    /// The MGEF carried no readable DATA, so nothing about it is known.
    case undecodedEffect
}

nonisolated enum MagicEffectPlanner {
    enum Outcome: Equatable {
        case apply(MagicEffectApplication)
        case skip(MagicEffectPlanFailure)
    }

    /// The archetypes this milestone implements. Everything else is counted and
    /// applies nothing.
    static let implementedArchetypes: Set<MagicEffectArchetype> = [
        .valueModifier, .dualValueModifier, .peakValueModifier
    ]

    /// Plans one effect entry.
    ///
    /// - Parameters:
    ///   - effect: the resolved MGEF, whose `sourcePlugin` the keyword link is
    ///     relative to.
    ///   - entry: the EFID/EFIT/CTDA entry that named it.
    ///   - isConstant: whether the record that carries the entry is a constant
    ///     effect — a worn item's enchantment (issue #472). Such an entry owns
    ///     its modifier slot until the item comes off, so its authored duration
    ///     of zero must not be read as "apply once".
    ///   - resolveKeyword: turns the MGEF's associated-item link into a key.
    ///     Supplied by the runtime, which owns the load order; a planner that
    ///     resolved links itself would need a store and stop being pure.
    static func plan(
        effect: ResolvedMagicEffect,
        entry: MagicItemEffect,
        isConstant: Bool = false,
        resolveKeyword: (FormID) -> ReferenceKey? = { _ in nil }
    ) -> Outcome {
        guard let data = effect.effect.data else {
            return .skip(.undecodedEffect)
        }
        guard implementedArchetypes.contains(data.archetype) else {
            return .skip(.unimplementedArchetype(data.archetype))
        }
        let duration = isConstant ? 0 : Float(entry.duration)
        let mode: ActiveEffectMode = if isConstant {
            .constant
        } else {
            data.flags.contains(.recover) ? .modifier : .perSecond
        }
        switch values(of: data, magnitude: entry.magnitude) {
        case let .failure(reason):
            return .skip(reason)
        case let .success(values):
            if
                mode.ownsModifierSlot, isConstant || duration > 0,
                let primary = values
                    .first(where: { ActorValueIdentity.kind(at: $0.index) != nil })
            {
                return .skip(.unsupportedPrimaryModifier(primary.index))
            }
            return .apply(MagicEffectApplication(
                effect: ReferenceKey(resolved: effect.id),
                archetype: data.archetype,
                mode: mode,
                isDetrimental: data.flags.contains(.detrimental),
                duration: duration,
                values: values,
                stackKeyword: data.archetype == .peakValueModifier
                    ? data.associatedItem.flatMap(resolveKeyword)
                    : nil,
                refusesRecast: data.flags.contains(.noRecast)
            ))
        }
    }

    // MARK: - Private

    /// The actor values one archetype acts on, or why it acts on none.
    private static func values(
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
