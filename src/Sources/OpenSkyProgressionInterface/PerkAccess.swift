// The seam other features read perks through. `PerkRuntime` in OpenSkyProgression
// conforms, and the composition root hands it to Magic as this protocol.

public import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData

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
        reading inputs: PerkInputs
    ) -> PerkEntryPointOutcome
}

/// What an entry-point evaluation reads besides the perks: the bound condition
/// subjects, nil for the owner alone, and each actor value by its index.
public struct PerkInputs {
    public var subjects: PerkEvaluationSubjects?
    public var actorValue: (Int32) -> Float?

    public init(
        subjects: PerkEvaluationSubjects? = nil,
        actorValue: @escaping (Int32) -> Float? = { _ in nil }
    ) {
        self.subjects = subjects
        self.actorValue = actorValue
    }
}

/// The default arguments a protocol requirement cannot carry.
extension PerkAccess {
    @discardableResult
    public mutating func modify(
        _ value: Float,
        at entryPoint: PerkEntryPoint,
        on holder: ActorValueHolder,
        subjects: PerkEvaluationSubjects? = nil,
        actorValue: @escaping (Int32) -> Float? = { _ in nil }
    ) -> PerkEntryPointOutcome {
        modify(
            value, at: entryPoint, on: holder,
            reading: PerkInputs(subjects: subjects, actorValue: actorValue)
        )
    }
}
