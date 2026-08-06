// CTDA condition evaluator (issue #251): the one place the engine asks "is this
// condition list true right now?".
//
// Nothing in here throws and nothing crashes. A condition the engine cannot yet
// answer — an unimplemented function, a global nothing defines, a run-on type
// with no live resolution — evaluates to false carrying a machine-readable
// `ConditionFailure`, and the same reason lands in `ConditionTally`. That makes
// missing coverage a measurable result rather than a silent wrong answer.
//
// Documented semantics, all from open sources rather than from memory:
//
//   Per-condition result is `functionReturn <operator> comparisonValue`, a
//   float comparison. No epsilon is applied to `==` / `!=`: neither UESP nor
//   the Creation Kit wiki documents a tolerance, so OpenSky compares exactly
//   and says so rather than inventing a fudge factor.
//
//   OR grouping (Creation Kit wiki "Conditions"): the OR flag on condition N
//   replaces the operator between N and N+1 with OR. Consecutive OR-joined
//   conditions form one disjunction block and blocks combine with AND, so OR
//   binds tighter than AND: the documented example `A AND B(or) C AND D`
//   evaluates as `A AND (B OR C) AND D`. An OR flag on the final condition has
//   no following operator to replace; the documented rule covers only that
//   operator, so OpenSky takes the conservative reading and simply ends the
//   block there. An empty condition list is true.
//
//   Run-on (UESP "CTDA Field", offset 20) selects the object the function runs
//   against. Subject, Target, Reference and Quest Alias resolve live through
//   `ConditionContext` — the last of those through the filled alias table
//   issue #183 added; every other type is a reason-tagged false with its own
//   tally bucket, never an error.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/CTDA Field"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CTDA_Field
//   Creation Kit wiki "Conditions" (OR-flag grouping)
//   xEdit dev Core/wbDefinitionsTES5.pas, `wbCTDA`

import Foundation

/// Why a condition could not be evaluated. Every case is a reason-tagged false
/// and a `ConditionTally` bucket.
///
/// The `Error` conformance exists only so these can ride in a `Result`; nothing
/// in the evaluator ever throws one, and no caller should catch one. Missing
/// coverage is a value here, not a control-flow event.
nonisolated enum ConditionFailure: Equatable, Error, Sendable {
    /// Raw on-disk function index with no registry entry (Creation Kit spells
    /// this number 4096 higher).
    case unknownFunction(UInt16)
    /// A `use global` comparison value, or a GLOB parameter, that resolves to
    /// no global. Deliberately not treated as zero.
    case unresolvedGlobal(FormID)
    /// A QUST parameter that resolves to no quest (issue #182). Deliberately
    /// not treated as a stopped quest at stage zero: "this quest does not
    /// exist" and "this quest has not started" are different answers, and only
    /// one of them is a real one.
    case unresolvedQuest(FormID)
    /// A run-on type OpenSky does not resolve live yet.
    case unsupportedRunOn(Condition.RunOnType)
    /// A supported run-on that named a reference the context cannot produce.
    case unresolvedReference(Condition.RunOnType)
    /// Operator bits 6 or 7, which are undefined on disk.
    case unknownOperator(UInt8)
    /// The named function needs a parameter it cannot read. Today that means a
    /// CIS1/CIS2 alias-name override that named no alias of the context's
    /// quest, or named one nothing has filled (issue #183). Carries the raw
    /// function index.
    case unresolvedParameter(UInt16)
    /// The function needs game time and the context carries no clock.
    case unavailableClock
}

/// The answer to one condition or one condition list.
///
/// `isTrue` is always usable: a condition that could not be evaluated is false
/// and names why in `failures`, so a caller that only wants a Bool never has to
/// handle an error path.
nonisolated struct ConditionOutcome: Equatable, Sendable {
    let isTrue: Bool
    /// Reasons for every condition that could not produce a real answer, in
    /// evaluation order. Empty when the whole list evaluated cleanly.
    let failures: [ConditionFailure]

    static let `true` = ConditionOutcome(isTrue: true, failures: [])
    static let `false` = ConditionOutcome(isTrue: false, failures: [])

    init(isTrue: Bool, failures: [ConditionFailure] = []) {
        self.isTrue = isTrue
        self.failures = failures
    }

    /// True when the outcome came from real answers rather than from a
    /// fallback.
    var isConclusive: Bool {
        failures.isEmpty
    }
}

/// Deterministic 0-99 source for `GetRandomPercent`.
///
/// A value type carrying its own state, so a caller injects a seed and gets a
/// reproducible sequence — the engine's live evaluator seeds it once per
/// session, and tests seed it per test. SplitMix64 (Steele, Lea and Flood,
/// "Fast splittable pseudorandom number generators", OOPSLA 2014) is used
/// because it is one multiply-free mixing step with no warm-up and no table.
nonisolated struct ConditionRandom: Equatable, Sendable {
    /// SplitMix64's golden-ratio increment, also this generator's default seed.
    static let defaultSeed: UInt64 = 0x9E37_79B9_7F4A_7C15

    private var state: UInt64

    init(seed: UInt64 = ConditionRandom.defaultSeed) {
        state = seed
    }

    /// Next raw 64-bit draw.
    mutating func next() -> UInt64 {
        state &+= Self.defaultSeed
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Next integer in 0...99 **inclusive** — `GetRandomPercent` never returns
    /// 100 (Creation Kit wiki "GetRandomPercent"). The modulo bias over a
    /// 64-bit draw is below one part in 2^57 and is not corrected for.
    mutating func percent() -> Int {
        Int(next() % 100)
    }
}

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

    /// One authored alias name as a parameter word, filled aliases only.
    private func aliasParameter(named name: String) -> Condition.Parameter? {
        guard
            let quest = context.aliasQuest,
            let aliasID = context.aliases.aliasID(named: name, in: quest),
            context.aliases.reference(alias: aliasID, in: quest) != nil
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
        let runOn = condition.runOn
        let swapped = condition.flags.contains(.swapSubjectAndTarget)
        switch runOn {
        case .subject:
            return entry(forKey: swapped ? context.target : context.subject, runOn: runOn)
        case .target:
            return entry(forKey: swapped ? context.subject : context.target, runOn: runOn)
        case .reference:
            guard let entry = context.references.entry(for: condition.reference) else {
                return .failure(.unresolvedReference(runOn))
            }
            return .success(entry)
        case .questAlias:
            return entry(forKey: questAliasKey(), runOn: runOn)
        default:
            return .failure(.unsupportedRunOn(runOn))
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

    private func entry(
        forKey key: ReferenceKey?,
        runOn: Condition.RunOnType
    ) -> Result<RuntimeReferenceEntry, ConditionFailure> {
        guard let key, let entry = context.references[key] else {
            return .failure(.unresolvedReference(runOn))
        }
        return .success(entry)
    }
}

/// Evaluates CTDA conditions and condition lists against a `ConditionContext`.
///
/// Mutating rather than pure because two things advance as it works: the tally,
/// and the random stream inside the context. Evaluation never short-circuits —
/// every condition in a list is evaluated even once the result is decided — so
/// the tally reports the full coverage picture of the list rather than only of
/// its prefix.
nonisolated struct ConditionEvaluator {
    var context: ConditionContext
    let registry: ConditionFunctionRegistry
    private(set) var tally: ConditionTally

    init(
        context: ConditionContext,
        registry: ConditionFunctionRegistry = .standard,
        tally: ConditionTally = ConditionTally()
    ) {
        self.context = context
        self.registry = registry
        self.tally = tally
    }

    // MARK: - Evaluation

    /// Evaluates one condition: `functionReturn <operator> comparisonValue`.
    mutating func evaluate(_ condition: Condition) -> ConditionOutcome {
        tally.noteCondition()
        switch result(of: condition) {
        case let .success(isTrue):
            return ConditionOutcome(isTrue: isTrue)
        case let .failure(failure):
            tally.note(failure)
            return ConditionOutcome(isTrue: false, failures: [failure])
        }
    }

    /// Evaluates a whole condition run with OR grouping (see the file header).
    /// An empty run is true, which is what an unconditioned record means.
    mutating func evaluate(_ conditions: [Condition]) -> ConditionOutcome {
        tally.noteList()
        guard !conditions.isEmpty else { return .true }

        var failures: [ConditionFailure] = []
        var result = true
        var block = false
        for condition in conditions {
            let outcome = evaluate(condition)
            failures.append(contentsOf: outcome.failures)
            block = block || outcome.isTrue
            if !condition.flags.contains(.or) {
                result = result && block
                block = false
            }
        }
        // A trailing OR flag has no following operator, so the last block ends
        // with the list rather than dangling.
        if conditions[conditions.count - 1].flags.contains(.or) {
            result = result && block
        }
        return ConditionOutcome(isTrue: result, failures: failures)
    }

    /// Convenience over a decoded `ConditionList`.
    mutating func evaluate(_ list: ConditionList) -> ConditionOutcome {
        evaluate(list.conditions)
    }

    // MARK: - One condition

    private mutating func result(of condition: Condition) -> Result<Bool, ConditionFailure> {
        guard let function = registry[condition.functionIndex] else {
            return .failure(.unknownFunction(condition.functionIndex))
        }
        var call = ConditionCall(condition: condition, context: context)
        let value = function.body(&call)
        context = call.context
        switch value {
        case let .failure(failure):
            return .failure(failure)
        case let .success(left):
            return comparisonValue(of: condition).flatMap { right in
                guard let isTrue = Self.compare(left, condition.comparison, right) else {
                    return .failure(.unknownOperator(Self.operatorBits(condition.comparison)))
                }
                return .success(isTrue)
            }
        }
    }

    /// The right-hand side, through the documented globals seam. A `use global`
    /// comparison naming no global is unevaluatable, never a compare to zero.
    private func comparisonValue(of condition: Condition) -> Result<Float, ConditionFailure> {
        switch condition.comparisonValue {
        case let .value(literal):
            return .success(literal)
        case let .global(id):
            guard let value = context.globals.comparisonValue(condition.comparisonValue) else {
                return .failure(.unresolvedGlobal(id))
            }
            return .success(value)
        }
    }

    /// Exact float comparison — see the file header on why no epsilon. Nil for
    /// the two undefined operator encodings.
    static func compare(
        _ left: Float,
        _ comparison: Condition.ComparisonOperator,
        _ right: Float
    ) -> Bool? {
        switch comparison {
        case .equal: left == right
        case .notEqual: left != right
        case .greaterThan: left > right
        case .greaterThanOrEqual: left >= right
        case .lessThan: left < right
        case .lessThanOrEqual: left <= right
        case .unknown: nil
        }
    }

    /// The raw top-3-bit encoding of an operator, for failure reporting.
    private static func operatorBits(_ comparison: Condition.ComparisonOperator) -> UInt8 {
        switch comparison {
        case .equal: 0
        case .notEqual: 1
        case .greaterThan: 2
        case .greaterThanOrEqual: 3
        case .lessThan: 4
        case .lessThanOrEqual: 5
        case let .unknown(raw): raw
        }
    }
}
