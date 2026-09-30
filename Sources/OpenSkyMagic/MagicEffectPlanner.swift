// Archetype dispatch: one decoded MGEF plus its EFIT numbers becomes what the
// runtime does. Pure. Value Modifier, Dual Value Modifier, and Peak Value
// Modifier follow <https://ck.uesp.net/wiki/Magic_Effect>; every other archetype
// is counted. The Detrimental flag sets direction. No Magnitude and No Duration
// are ignored, as the wiki says they change only the editor.
// See docs/engine/magic.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// One MGEF entry resolved into an application the runtime can carry out.
nonisolated public struct MagicEffectApplication: Equatable, Sendable {
    /// The MGEF being applied.
    public let effect: ReferenceKey
    /// Which of the two documented timed behaviours applies. Meaningless for an
    /// instant application, which is applied once and stored nowhere.
    public let mode: ActiveEffectMode
    public let isDetrimental: Bool
    /// EFIT duration in seconds; zero for an instantaneous effect.
    public let duration: Float
    /// The actor values acted on, first value first.
    public let values: [ActiveEffectValue]
    /// Peak Value Modifier's second associated item.
    public let stackKeyword: ReferenceKey?
    /// MGEF No Recast: "Once the magic effect is applied to a target, it cannot
    /// be cast again on the same target until it has worn off or been
    /// dispelled."
    public let refusesRecast: Bool

    /// Whether the effect applies once rather than persisting. A constant effect also
    /// has zero duration but persists, so the mode is checked first.
    public var isInstant: Bool {
        mode != .constant && duration <= 0
    }
}

/// Why one effect entry produced no application. Every case is a tally bucket,
/// never an error: a potion with one unimplemented effect still applies its
/// other ones.
/// The `Error` conformance exists only so these can ride in a `Result`; nothing
/// here ever throws one, exactly as `ConditionFailure` documents.
nonisolated public enum MagicEffectPlanFailure: Equatable, Error, Hashable, Sendable {
    /// The archetype has no implementation in this milestone.
    case unimplementedArchetype(MagicEffectArchetype)
    /// The archetype is implemented but the record names no actor value inside
    /// the vanilla table — usually -1, "none".
    case unaddressableValue(Int32)
    /// The MGEF carried no readable DATA, so nothing about it is known.
    case undecodedEffect
}

nonisolated public enum MagicEffectPlanner: Sendable {
    public enum Outcome: Equatable, Sendable {
        case apply(MagicEffectApplication)
        case skip(MagicEffectPlanFailure)
    }

    /// The archetypes this milestone implements. Everything else is counted and
    /// applies nothing.
    public static let implementedArchetypes: Set<MagicEffectArchetype> = [
        .valueModifier, .dualValueModifier, .peakValueModifier
    ]

    /// Plans one EFID/EFIT/CTDA `entry` of the resolved MGEF `effect`.
    /// `isConstant` marks a worn enchantment, whose zero duration means "while
    /// worn". `resolveKeyword` turns the plugin-relative keyword link into a key,
    /// so the planner stays pure.
    public static func plan(
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
            // A timed Recover effect on health, magicka, or stamina applies like any held
            // modifier: a primary's temporary slot moves its maximum and the current value.
            // Expiry's floor is `ActiveEffectRuntime.release`.
            return .apply(MagicEffectApplication(
                effect: ReferenceKey(resolved: effect.id),
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
