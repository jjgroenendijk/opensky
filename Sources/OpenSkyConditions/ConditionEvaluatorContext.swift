// The inputs to a condition: `ConditionContext` (what it may read) and
// `ConditionCall` (how a run-on picks its object). `ConditionEvaluator.swift` holds
// the machinery: comparison, OR grouping and the tally.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// A feature's condition seam: the state its condition functions read,
/// resolved for one evaluation. A context holds at most one value per type,
/// and a type the caller did not set reads as `empty`.
///
/// `empty` is what a context with no world running carries, and it makes every
/// function that reads it a reason-tagged false rather than a convincing zero.
nonisolated public protocol ConditionResolution: Sendable {
    static var empty: Self { get }
}

/// The quest-alias lookups the core itself needs: the CIS1/CIS2 name
/// overrides and the Quest Alias run-on. The quest module conforms to it.
nonisolated public protocol ConditionAliasResolving: Sendable {
    func aliasID(named name: String, in quest: FormID) -> UInt32?
    func reference(alias aliasID: UInt32, in quest: FormID) -> ReferenceKey?
    func location(alias aliasID: UInt32, in quest: FormID) -> ResolvedFormID?
}

/// The combat-target lookup the Combat Target run-on needs. The actor module
/// conforms to it.
nonisolated public protocol ConditionCombatTargetResolving: Sendable {
    func combatTarget(of key: ReferenceKey) -> ReferenceKey?
}

/// Everything a condition is evaluated against. A cheap value type, so off-main-actor
/// code builds one from a snapshot. Feature seams are stored by type
/// (`ConditionResolution`); each feature adds an accessor such as `context.magic`.
nonisolated public struct ConditionContext: Sendable {
    /// The one seam global values come through (`GlobalResolution`).
    public var globals: GlobalResolution = .empty
    /// Load-order keyword, form-list and location stores plus the current and
    /// editor location facts for references. Empty when no data snapshot is
    /// available, so the record-data functions report an honest unavailable
    /// result rather than a convincing zero.
    public var data: ConditionDataResolution = .empty
    /// Runtime enable overrides for `GetDisabled`. When absent for a key, the
    /// function falls back to the placement record's initial flag.
    public var referenceEnable: ReferenceEnableResolution = .empty
    /// The quest a `questAlias` run-on and a CIS1/CIS2 override resolve against. A CTDA
    /// names no quest; the owning record does. Nil makes every alias path a tagged failure.
    public var aliasQuest: FormID?
    /// From the plugin the conditions were written in to the space the stores use.
    /// Nil when both are the same, as for `Skyrim.esm` records.
    public var formIDTranslation: FormIDTranslation?
    /// Game clock the time functions read. Nil in a context with no world
    /// running, which makes those functions reason-tagged false rather than
    /// wrong.
    public var clock: GameClock?
    /// References the Subject/Target/Reference run-ons resolve against.
    public var references: RuntimeReferenceIndex = .empty
    /// The object the condition is being asked about (run-on 0).
    public var subject: ReferenceKey?
    /// The other party in the interaction (run-on 1).
    public var target: ReferenceKey?
    public var random = ConditionRandom()
    /// The alias seam the core reads. The quest module sets it together with
    /// its own resolution. Nil makes every alias path a reason-tagged failure.
    public var aliasResolver: (any ConditionAliasResolving)?
    /// The combat-target seam the core reads. The actor module sets it
    /// together with its own resolution.
    public var combatTargetResolver: (any ConditionCombatTargetResolving)?
    /// The story-manager event being walked. The Event Data run-on reads it.
    public var event: StoryEventData?

    private var resolutions: [ObjectIdentifier: any ConditionResolution] = [:]

    public init() {}

    /// The resolution of `type` this context carries, or `type.empty`.
    public subscript<Resolution: ConditionResolution>(
        resolution type: Resolution.Type
    ) -> Resolution {
        get { resolutions[ObjectIdentifier(type)] as? Resolution ?? .empty }
        set { resolutions[ObjectIdentifier(type)] = newValue }
    }
}

/// One function invocation: the condition being evaluated plus the context it
/// runs against. Passed `inout` so a function that consumes randomness advances
/// the caller's stream.
nonisolated public struct ConditionCall: Sendable {
    public let condition: Condition
    public var context: ConditionContext

    /// Parameter #1, with CIS1 first when present. A CIS1 name resolves to the alias
    /// ID; `aliasReference(_:)` gives the reference. An unmatched or unfilled name is
    /// nil, which becomes `ConditionFailure.unresolvedParameter`.
    public var parameter1: Condition.Parameter? {
        guard let name = condition.parameter1Name else { return condition.parameter1 }
        return aliasParameter(named: name)
    }

    public var parameter2: Condition.Parameter? {
        guard let name = condition.parameter2Name else { return condition.parameter2 }
        return aliasParameter(named: name)
    }

    /// Reference filling the alias `parameter` names on the context's quest, or
    /// nil when there is no quest scope, no such alias, or nothing in it.
    public func aliasReference(_ parameter: Condition.Parameter) -> ReferenceKey? {
        guard let quest = context.aliasQuest else { return nil }
        return context.aliasResolver?.reference(alias: parameter.rawValue, in: quest)
    }

    /// Location filling the alias `parameter` names on the context's quest.
    public func aliasLocation(_ parameter: Condition.Parameter) -> ResolvedFormID? {
        guard let quest = context.aliasQuest else { return nil }
        return context.aliasResolver?.location(alias: parameter.rawValue, in: quest)
    }

    /// One authored alias name as a parameter word, filled aliases only.
    private func aliasParameter(named name: String) -> Condition.Parameter? {
        guard
            let quest = context.aliasQuest,
            let aliases = context.aliasResolver,
            let aliasID = aliases.aliasID(named: name, in: quest),
            aliases.reference(alias: aliasID, in: quest) != nil
            || aliases.location(alias: aliasID, in: quest) != nil
        else {
            return nil
        }
        return Condition.Parameter(rawValue: aliasID)
    }

    /// The reference the run-on names, honouring `swapSubjectAndTarget` (0x10). Fails
    /// as `.unsupportedRunOn` or `.unresolvedReference`. Quest Alias (run-on 5) reads
    /// parameter #3 (CTDA offset 28) against the context's `aliasQuest`.
    public func reference() -> Result<RuntimeReferenceEntry, ConditionFailure> {
        referenceKey().flatMap { key in
            guard let entry = context.references[key] else {
                return .failure(.unresolvedReference(condition.runOn))
            }
            return .success(entry)
        }
    }

    /// Whether this condition's run-on reference is disabled right now.
    /// Runtime state wins; otherwise the REFR/ACHR header's initial flag is the
    /// plugin baseline. A missing placement is not treated as disabled.
    public func referenceIsDisabled() -> Result<Bool, ConditionFailure> {
        referenceKey().flatMap { key in
            if let state = context.referenceEnable[key] {
                return .success(!state.isEnabled)
            }
            guard let entry = context.references[key] else {
                return .failure(.unresolvedReference(condition.runOn))
            }
            switch entry.record {
            case let .reference(reference):
                return .success(reference.isInitiallyDisabled)
            case let .actor(actor):
                return .success(actor.isInitiallyDisabled)
            }
        }
    }

    /// The identity the run-on names, without a decoded record. `GetIsID` needs the
    /// record; actor functions need only identity, and the player has no record.
    public func referenceKey() -> Result<ReferenceKey, ConditionFailure> {
        let runOn = condition.runOn
        let swapped = condition.flags.contains(.swapSubjectAndTarget)
        switch runOn {
        case .subject:
            return key(swapped ? context.target : context.subject, runOn: runOn)
        case .target:
            return key(swapped ? context.subject : context.target, runOn: runOn)
        case .reference:
            guard let entry = referenceEntry(condition.reference) else {
                return .failure(.unresolvedReference(runOn))
            }
            return .success(entry.key)
        case .combatTarget:
            return key(combatTargetKey(swapped: swapped), runOn: runOn)
        case .questAlias:
            return key(questAliasKey(), runOn: runOn)
        case .eventData:
            let member = StoryEventData
                .Member(rawValue: UInt16(truncatingIfNeeded: condition.parameter3))
            return key(member.flatMap { context.event?.reference($0) }, runOn: runOn)
        default:
            return .failure(.unsupportedRunOn(runOn))
        }
    }

    /// The reference the subject is fighting (run-on type 3), from the actor seam.
    /// Both sides of a fight answer. Nil is `.unresolvedReference`.
    private func combatTargetKey(swapped: Bool) -> ReferenceKey? {
        guard let subject = swapped ? context.target : context.subject else {
            return nil
        }
        return context.combatTargetResolver?.combatTarget(of: subject)
    }

    /// The reference filling the alias this condition's run-on names, or nil
    /// when the index is the unused -1, there is no quest scope, or the alias
    /// is empty. All three are one `.unresolvedReference` — the run-on itself
    /// is supported now, so `.unsupportedRunOn` would be the wrong reason.
    private func questAliasKey() -> ReferenceKey? {
        guard
            condition.parameter3 >= 0,
            let quest = context.aliasQuest
        else {
            return nil
        }
        return context.aliasResolver?.reference(
            alias: UInt32(bitPattern: condition.parameter3), in: quest
        )
    }

    /// The placement `formID` names. A translated ID is in the stores' space, but a
    /// cell index keeps each reference as its own plugin wrote it, so the key is tried first.
    public func referenceEntry(_ formID: FormID) -> RuntimeReferenceEntry? {
        if
            let target = context.formIDTranslation?.target,
            let key = ReferenceKey.resolve(formID, using: target),
            let entry = context.references[key]
        {
            return entry
        }
        return context.references.entry(for: formID)
    }

    /// The game clock, or `.unavailableClock`.
    public func clock() -> Result<GameClock, ConditionFailure> {
        guard let clock = context.clock else { return .failure(.unavailableClock) }
        return .success(clock)
    }

    /// Current value of the global `id` names, or `.unresolvedGlobal`.
    public func global(_ id: FormID) -> Result<Float, ConditionFailure> {
        guard let value = context.globals.floatValue(for: id) else {
            return .failure(.unresolvedGlobal(id))
        }
        return .success(value)
    }

    public mutating func randomPercent() -> Int {
        context.random.percent()
    }

    private func key(
        _ key: ReferenceKey?,
        runOn: Condition.RunOnType
    ) -> Result<ReferenceKey, ConditionFailure> {
        guard let key else { return .failure(.unresolvedReference(runOn)) }
        return .success(key)
    }

    public init(condition: Condition, context: ConditionContext) {
        self.condition = condition
        self.context = context
    }
}
