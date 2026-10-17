// The seam other features read perks through. `PerkRuntime` in OpenSkyProgression
// conforms, and the composition root hands it to Magic as this protocol.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// Which perks an actor owns, and what they do to a value at an entry point.
@MainActor
public protocol PerkAccess {
    /// The perk records the load order defines.
    var perks: PerkStore { get }

    /// The seams the entry-point conditions read, such as the spell being cast.
    var conditions: ConditionContext { get set }

    /// Whether `holder` owns `perk`.
    func owns(_ perk: ReferenceKey, on holder: ActorValueHolder) -> Bool

    /// Every perk `holder` owns that the load order still defines, in key order.
    func ownedPerks(of holder: ActorValueHolder) -> [ResolvedPerk]

    /// What `holder`'s perks do to `value` at `entryPoint`. An entry point nothing
    /// hooks answers with the value it was handed.
    @discardableResult
    mutating func modify(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects?,
        actorValue: (Int32) -> Float?
    ) -> PerkEntryPointOutcome

    /// The effects at `entryPoint` that pick a spell, a text, or a button for `holder`,
    /// highest priority first.
    mutating func choices(
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects
    ) -> [PerkEntryPointChoice]
}
