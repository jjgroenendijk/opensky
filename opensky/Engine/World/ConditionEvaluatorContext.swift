// The value a condition is evaluated against, and one function invocation over
// it (issue #251), split out of `ConditionEvaluator.swift` when that file
// reached its size cap.
//
// The split is along a real seam rather than an arbitrary line count.
// `ConditionEvaluator` is the machinery: comparison, OR grouping, the tally.
// `ConditionContext` and `ConditionCall` are the *inputs* — which seams a
// condition may read and how a run-on picks the object it runs against — and
// they are what a caller builds and what a condition function body talks to.
// A reader wiring a new evaluation site needs this file; a reader changing how
// a list combines needs the other one.

import Foundation

/// Everything a condition is evaluated against: the globals seam, the game
/// clock, the reference index, which references the Subject and Target run-ons
/// name, and the random source.
///
/// A value type on purpose. Building one is cheap, so a caller evaluating
/// against a snapshot off the main actor builds its own rather than reaching
/// into live stores.
nonisolated struct ConditionContext: Sendable {
    /// The one seam global values come through (`GlobalResolution`).
    var globals: GlobalResolution
    /// The one seam quest state comes through (issue #182), shaped exactly like
    /// the globals seam: a value resolving overrides over plugin baselines, so
    /// the quest functions never reach into `WorldStateStore`.
    var quests: QuestResolution
    /// The one seam filled quest aliases come through (issue #183). Separate
    /// from `quests` because the two answer different questions and a caller
    /// may legitimately have one and not the other.
    var aliases: QuestAliasResolution
    /// The one seam actor values, death, hostility and the combat target come
    /// through (issue #375), shaped exactly like the two above. Empty in a
    /// context with no world running, which makes every actor function a
    /// reason-tagged false rather than a convincing zero.
    var actors: ActorStateResolution
    /// The one seam the perception pass comes through (issue #202), shaped
    /// exactly like the four above. Empty in a context with no world running,
    /// which makes every detection function a reason-tagged false rather than a
    /// convincing "not detected".
    var detection: DetectionResolution
    /// The one seam dialogue facts come through (issue #426), shaped exactly
    /// like the five above: an actor's voice type and who the player is talking
    /// to. Empty in a context with no world running, which makes every dialogue
    /// function a reason-tagged false rather than a convincing "no voice type".
    var dialogue: DialogueResolution
    /// Load-order keyword, form-list and location stores plus the current and
    /// editor location facts for references (issue #455). Empty when no data
    /// snapshot is available, so M18 functions report an honest unavailable
    /// result rather than a convincing zero.
    var data: ConditionDataResolution
    /// Known spells, active effects and cast state per actor, plus the SPEL
    /// and MGEF stores their FormID parameters resolve against (issue #474).
    /// Empty when no magic runtime is wired, which makes every magic function
    /// a reason-tagged false rather than an actor who has learned nothing.
    var magic: MagicConditionResolution
    /// Owned perks per actor plus the PERK store `HasPerk`'s parameter resolves
    /// against (issue #497). Empty when no perk runtime is wired, which makes
    /// `HasPerk` a reason-tagged false rather than an actor who has taken
    /// nothing.
    var perks: PerkConditionResolution
    /// Runtime enable overrides for `GetDisabled`. When absent for a key, the
    /// function falls back to the placement record's initial flag.
    var referenceEnable: ReferenceEnableResolution
    /// Quest whose alias table a `questAlias` run-on and a CIS1/CIS2 name
    /// override are resolved against.
    ///
    /// Alias references are only meaningful relative to an owning quest, and a
    /// CTDA does not carry one: the record the condition was read from does.
    /// A QUST's own condition runs are evaluated with that quest here; a
    /// dialogue or package condition is evaluated with the quest that owns the
    /// topic. Nil means the caller had no quest scope, which makes every alias
    /// path a reason-tagged failure rather than a wrong answer.
    var aliasQuest: FormID?
    /// Game clock the time functions read. Nil in a context with no world
    /// running, which makes those functions reason-tagged false rather than
    /// wrong.
    var clock: GameClock?
    /// References the Subject/Target/Reference run-ons resolve against.
    var references: RuntimeReferenceIndex
    /// The object the condition is being asked about (run-on 0).
    var subject: ReferenceKey?
    /// The other party in the interaction (run-on 1).
    var target: ReferenceKey?
    var random: ConditionRandom

    init(
        globals: GlobalResolution = .empty,
        quests: QuestResolution = .empty,
        aliases: QuestAliasResolution = .empty,
        actors: ActorStateResolution = .empty,
        detection: DetectionResolution = .empty,
        dialogue: DialogueResolution = .empty,
        data: ConditionDataResolution = .empty,
        magic: MagicConditionResolution = .empty,
        perks: PerkConditionResolution = .empty,
        referenceEnable: ReferenceEnableResolution = .empty,
        aliasQuest: FormID? = nil,
        clock: GameClock? = nil,
        references: RuntimeReferenceIndex = .empty,
        subject: ReferenceKey? = nil,
        target: ReferenceKey? = nil,
        random: ConditionRandom = ConditionRandom()
    ) {
        self.globals = globals
        self.quests = quests
        self.aliases = aliases
        self.actors = actors
        self.detection = detection
        self.dialogue = dialogue
        self.data = data
        self.magic = magic
        self.perks = perks
        self.referenceEnable = referenceEnable
        self.aliasQuest = aliasQuest
        self.clock = clock
        self.references = references
        self.subject = subject
        self.target = target
        self.random = random
    }
}

/// One function invocation: the condition being evaluated plus the context it
/// runs against. Passed `inout` so a function that consumes randomness advances
/// the caller's stream.
nonisolated struct ConditionCall: Sendable {
    let condition: Condition
    var context: ConditionContext

    /// Parameter #1, with CIS1 taking precedence when the record carried one.
    ///
    /// A CIS1 string names a quest alias rather than a form, so the resolved
    /// parameter is that alias's *ID* — the number every other alias-typed
    /// parameter on disk carries — and a caller wanting the reference behind it
    /// asks `aliasReference(_:)`. A name that matches no alias of the context's
    /// quest, or one nothing has filled, reports nil, and the function turns
    /// that into `ConditionFailure.unresolvedParameter` (issue #183).
    var parameter1: Condition.Parameter? {
        guard let name = condition.parameter1Name else { return condition.parameter1 }
        return aliasParameter(named: name)
    }

    var parameter2: Condition.Parameter? {
        guard let name = condition.parameter2Name else { return condition.parameter2 }
        return aliasParameter(named: name)
    }

    /// Reference filling the alias `parameter` names on the context's quest, or
    /// nil when there is no quest scope, no such alias, or nothing in it.
    func aliasReference(_ parameter: Condition.Parameter) -> ReferenceKey? {
        guard let quest = context.aliasQuest else { return nil }
        return context.aliases.reference(alias: parameter.rawValue, in: quest)
    }

    /// Location filling the alias `parameter` names on the context's quest.
    func aliasLocation(_ parameter: Condition.Parameter) -> ResolvedFormID? {
        guard let quest = context.aliasQuest else { return nil }
        return context.aliases.location(alias: parameter.rawValue, in: quest)
    }

    /// One authored alias name as a parameter word, filled aliases only.
    private func aliasParameter(named name: String) -> Condition.Parameter? {
        guard
            let quest = context.aliasQuest,
            let aliasID = context.aliases.aliasID(named: name, in: quest),
            context.aliases.reference(alias: aliasID, in: quest) != nil
            || context.aliases.location(alias: aliasID, in: quest) != nil
        else {
            return nil
        }
        return Condition.Parameter(rawValue: aliasID)
    }

    /// The reference this condition's run-on names.
    ///
    /// The `swapSubjectAndTarget` flag (0x10) is honoured here, which is the
    /// only place it can matter. Run-on types with no live resolution fail as
    /// `.unsupportedRunOn`; a supported run-on naming nothing the index holds
    /// fails as `.unresolvedReference`. Only functions that actually need a
    /// reference ask for one, so a time function still answers under a run-on
    /// OpenSky cannot resolve.
    ///
    /// Quest Alias (run-on 5) resolves through the filled table (issue #183).
    /// Its alias number is parameter #3 at CTDA offset 28, "the quest-alias /
    /// package-data index" — see `Condition` — and the quest it belongs to is
    /// the context's `aliasQuest`, because a CTDA does not name one.
    func reference() -> Result<RuntimeReferenceEntry, ConditionFailure> {
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
    func referenceIsDisabled() -> Result<Bool, ConditionFailure> {
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

    /// The world identity this condition's run-on names, without requiring the
    /// reference index to hold a decoded record for it.
    ///
    /// Split out of `reference()` because the two questions genuinely differ
    /// (issue #375). `GetIsID` needs the decoded placement, because it compares
    /// base forms; the actor functions need only identity, and the player has a
    /// `ReferenceKey` and no plugin record at all. Asking for the record first
    /// would have made every actor condition about the player an unresolved
    /// reference — a failure with nothing wrong behind it.
    func referenceKey() -> Result<ReferenceKey, ConditionFailure> {
        let runOn = condition.runOn
        let swapped = condition.flags.contains(.swapSubjectAndTarget)
        switch runOn {
        case .subject:
            return key(swapped ? context.target : context.subject, runOn: runOn)
        case .target:
            return key(swapped ? context.subject : context.target, runOn: runOn)
        case .reference:
            guard let entry = context.references.entry(for: condition.reference) else {
                return .failure(.unresolvedReference(runOn))
            }
            return .success(entry.key)
        case .combatTarget:
            return key(combatTargetKey(swapped: swapped), runOn: runOn)
        case .questAlias:
            return key(questAliasKey(), runOn: runOn)
        default:
            return .failure(.unsupportedRunOn(runOn))
        }
    }

    /// The reference this condition's *subject* is fighting (issue #375).
    ///
    /// Run-on type 3 asks about the combat target of the object the condition
    /// runs against, so it is resolved by looking the subject up in the actor
    /// seam rather than by reading one session-wide "the fight". 15.7 derives
    /// the player's target and gives each hostile actor the player as its own,
    /// so both directions of a fight answer. Nil — no subject bound, no actor
    /// state for it, or an actor fighting nobody — is one
    /// `.unresolvedReference`, because the run-on itself is supported now.
    private func combatTargetKey(swapped: Bool) -> ReferenceKey? {
        guard let subject = swapped ? context.target : context.subject else {
            return nil
        }
        return context.actors.combatTarget(of: subject)
    }

    /// Actor state for this condition's run-on reference, or
    /// `.unavailableActorState`.
    ///
    /// Note the two-step: the run-on has to name a reference the index holds
    /// *and* the actor seam has to carry state for it. The first failure is
    /// `.unresolvedReference` and stays that way, because "the run-on named
    /// nothing" and "the named thing is not an actor this session tracks" are
    /// different gaps and only one of them is about actors.
    func actorState() -> Result<ActorConditionState, ConditionFailure> {
        referenceKey().flatMap { key in
            guard let state = context.actors.state(for: key) else {
                return .failure(.unavailableActorState)
            }
            return .success(state)
        }
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
        return context.aliases.reference(
            alias: UInt32(bitPattern: condition.parameter3), in: quest
        )
    }

    /// The game clock, or `.unavailableClock`.
    func clock() -> Result<GameClock, ConditionFailure> {
        guard let clock = context.clock else { return .failure(.unavailableClock) }
        return .success(clock)
    }

    /// Current value of the global `id` names, or `.unresolvedGlobal`.
    func global(_ id: FormID) -> Result<Float, ConditionFailure> {
        guard let value = context.globals.floatValue(for: id) else {
            return .failure(.unresolvedGlobal(id))
        }
        return .success(value)
    }

    /// Current state of the quest `id` names, or `.unresolvedQuest`.
    func quest(_ id: FormID) -> Result<QuestRuntimeState, ConditionFailure> {
        guard let state = context.quests.state(for: id) else {
            return .failure(.unresolvedQuest(id))
        }
        return .success(state)
    }

    mutating func randomPercent() -> Int {
        context.random.percent()
    }

    private func key(
        _ key: ReferenceKey?,
        runOn: Condition.RunOnType
    ) -> Result<ReferenceKey, ConditionFailure> {
        guard let key else { return .failure(.unresolvedReference(runOn)) }
        return .success(key)
    }
}
