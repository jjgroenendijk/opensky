// What the condition evaluator could not answer (issue #251).
//
// The evaluator never throws and never crashes: a condition it cannot answer
// becomes a reason-tagged false plus one tally entry. That makes the tally a
// first-class result rather than a debug aid — it is the coverage evidence for
// "which CTDA functions does OpenSky still owe Skyrim?", the same role
// `AS2Tally` plays for ActionScript, and it is what the real-data sweep reads.
//
// Every name table is capped so a pathological plugin cannot grow the tally
// without bound, and every total keeps counting past its cap: a truncated table
// still reports how much it stopped naming.

import Foundation

/// Counts of everything the condition evaluator could not evaluate, plus the
/// volume it did evaluate.
nonisolated struct ConditionTally: Equatable, Sendable {
    /// Distinct keys kept per table.
    static let defaultNameLimit = 64

    let nameLimit: Int

    /// Raw function index -> times it was hit with no registry entry.
    private(set) var unknownFunctions: [UInt16: Int] = [:]
    /// Every unknown-function hit, including ones past `nameLimit`.
    private(set) var unknownFunctionTotal = 0
    /// Unknown-function hits that arrived after `unknownFunctions` was full.
    private(set) var unnamedUnknownFunctions = 0

    /// GLOB FormID -> times a comparison or a function could not resolve it.
    private(set) var unresolvedGlobals: [FormID: Int] = [:]
    private(set) var unresolvedGlobalTotal = 0
    private(set) var unnamedUnresolvedGlobals = 0

    /// QUST FormID -> times a quest function could not resolve it (issue #182).
    private(set) var unresolvedQuests: [FormID: Int] = [:]
    private(set) var unresolvedQuestTotal = 0
    private(set) var unnamedUnresolvedQuests = 0

    /// Run-on bucket name -> times that run-on type has no live resolution.
    /// Keyed by `ConditionTally.runOnName(_:)` so the report reads as
    /// `combatTarget`, `questAlias`, `unknown(9)`, and so on.
    private(set) var unsupportedRunOns: [String: Int] = [:]
    private(set) var unsupportedRunOnTotal = 0

    /// Run-on bucket name -> times a supported run-on named a reference the
    /// context could not produce (no subject bound, key not in the index).
    private(set) var unresolvedReferences: [String: Int] = [:]
    private(set) var unresolvedReferenceTotal = 0

    /// Raw operator bits 6 and 7, which are undefined on disk.
    private(set) var unknownOperators: [UInt8: Int] = [:]
    private(set) var unknownOperatorTotal = 0

    /// Function index -> times its parameters could not be read.
    private(set) var unresolvedParameters: [UInt16: Int] = [:]
    private(set) var unresolvedParameterTotal = 0

    /// Conditions that needed a game clock in a context that has none.
    private(set) var unavailableClock = 0

    /// Conditions that needed actor state the context carries none of (issue
    /// #375): an unknown actor, or one whose weapon draw state nothing
    /// observes.
    private(set) var unavailableActorState = 0

    /// Conditions that needed perception the context carries none of (issue
    /// #202): a pair the pass is not watching, or a reference it cannot place.
    private(set) var unavailableDetection = 0

    /// Conditions that needed a dialogue fact the context carries none of
    /// (issue #426): a run-on reference this session resolved no voice type
    /// for. Deliberately not treated as a voice-type mismatch, which is a
    /// different answer.
    private(set) var unavailableDialogue = 0

    /// M18 store or resolution misses, grouped by the domain that could not
    /// answer rather than silently counted as a negative match.
    private(set) var unavailableData: [ConditionDataDomain: Int] = [:]

    /// Magic seam misses (issue #474), grouped the same way and for the same
    /// reason: an actor with no magic state and a casting source OpenSky
    /// readies nothing into are different gaps.
    private(set) var unavailableMagic: [ConditionMagicDomain: Int] = [:]

    /// Perk seam misses (issue #497): `HasPerk` in a session with no PERK data,
    /// or against a parameter no loaded plugin carries. Deliberately not
    /// counted as an actor who has not taken the perk.
    private(set) var unavailablePerks = 0

    /// Crime seam misses (issue #504): `GetCrimeGold` in a session with no FACT
    /// data, against a parameter no loaded plugin carries, or with a null
    /// parameter outside any hold. Deliberately not counted as an actor who
    /// owes nothing.
    private(set) var unavailableCrime = 0

    private(set) var conditionsEvaluated = 0
    private(set) var listsEvaluated = 0

    init(nameLimit: Int = ConditionTally.defaultNameLimit) {
        self.nameLimit = max(0, nameLimit)
    }

    // MARK: - Recording

    /// Records one evaluated condition, whatever the outcome.
    mutating func noteCondition() {
        conditionsEvaluated += 1
    }

    /// Records one evaluated condition list, including an empty one.
    mutating func noteList() {
        listsEvaluated += 1
    }

    /// Routes a failure into its bucket. The evaluator calls this for every
    /// reason-tagged false so no caller has to match on the reason itself.
    mutating func note(_ failure: ConditionFailure) {
        // Read out of `self` first: passing a stored property `inout` to a
        // method on `self` would be an overlapping access.
        let limit = nameLimit
        switch failure {
        case let .unknownFunction(index):
            noteUnimplemented(functionIndex: index)
        case let .unresolvedGlobal(id):
            noteUnresolvedGlobal(id)
        case let .unresolvedQuest(id):
            noteUnresolvedQuest(id)
        case let .unsupportedRunOn(runOn):
            unsupportedRunOnTotal += 1
            Self.bump(&unsupportedRunOns, Self.runOnName(runOn), limit: limit)
        case let .unresolvedReference(runOn):
            unresolvedReferenceTotal += 1
            Self.bump(&unresolvedReferences, Self.runOnName(runOn), limit: limit)
        case let .unknownOperator(bits):
            unknownOperatorTotal += 1
            Self.bump(&unknownOperators, bits, limit: limit)
        case let .unresolvedParameter(index):
            unresolvedParameterTotal += 1
            Self.bump(&unresolvedParameters, index, limit: limit)
        case .unavailableClock, .unavailableActorState, .unavailableDetection,
             .unavailableDialogue, .unavailableData, .unavailableMagic,
             .unavailablePerks, .unavailableCrime:
            noteUnavailable(failure)
        }
    }

    /// The "this session carries no such state" half, split out because the one
    /// switch outgrew the strict-lint complexity cap once the magic seam landed.
    /// The caller's switch stays exhaustive, so a new failure case still fails
    /// to compile there rather than falling silently into this default.
    private mutating func noteUnavailable(_ failure: ConditionFailure) {
        switch failure {
        case .unavailableClock:
            unavailableClock += 1
        case .unavailableActorState:
            unavailableActorState += 1
        case .unavailableDetection:
            unavailableDetection += 1
        case .unavailableDialogue:
            unavailableDialogue += 1
        case let .unavailableData(domain):
            unavailableData[domain, default: 0] += 1
        case let .unavailableMagic(domain):
            unavailableMagic[domain, default: 0] += 1
        case .unavailablePerks:
            unavailablePerks += 1
        case .unavailableCrime:
            unavailableCrime += 1
        default:
            break
        }
    }

    /// A function index the registry has no implementation for. Mirrors
    /// `AS2Tally.noteUnimplemented(opcode:)`; the index is the raw on-disk
    /// number, which the Creation Kit spells 4096 higher.
    mutating func noteUnimplemented(functionIndex: UInt16) {
        unknownFunctionTotal += 1
        if unknownFunctions[functionIndex] != nil || unknownFunctions.count < nameLimit {
            unknownFunctions[functionIndex, default: 0] += 1
        } else {
            unnamedUnknownFunctions += 1
        }
    }

    mutating func noteUnresolvedGlobal(_ id: FormID) {
        unresolvedGlobalTotal += 1
        if unresolvedGlobals[id] != nil || unresolvedGlobals.count < nameLimit {
            unresolvedGlobals[id, default: 0] += 1
        } else {
            unnamedUnresolvedGlobals += 1
        }
    }

    mutating func noteUnresolvedQuest(_ id: FormID) {
        unresolvedQuestTotal += 1
        if unresolvedQuests[id] != nil || unresolvedQuests.count < nameLimit {
            unresolvedQuests[id, default: 0] += 1
        } else {
            unnamedUnresolvedQuests += 1
        }
    }

    private static func bump<Key: Hashable>(
        _ table: inout [Key: Int],
        _ key: Key,
        limit: Int
    ) {
        if table[key] != nil || table.count < limit {
            table[key, default: 0] += 1
        }
    }

    // MARK: - Reporting

    /// True when every condition evaluated produced a real answer.
    var isClean: Bool {
        failureTotal == 0
    }

    /// Every reason-tagged false, across all buckets.
    var failureTotal: Int {
        unknownFunctionTotal + unresolvedGlobalTotal + unresolvedQuestTotal
            + unsupportedRunOnTotal + unresolvedReferenceTotal + unknownOperatorTotal
            + unresolvedParameterTotal + unavailableClock + unavailableActorState
            + unavailableDetection + unavailableDialogue
            + unavailableData.values.reduce(0, +)
            + unavailableMagic.values.reduce(0, +) + unavailablePerks
            + unavailableCrime
    }

    /// Unknown function indices ranked by count, ties broken by index so the
    /// order is stable. Names come from the registry's documented list where it
    /// has one, and are the bare index otherwise.
    func rankedUnknownFunctions(
        in registry: ConditionFunctionRegistry = .standard
    ) -> [(name: String, count: Int)] {
        unknownFunctions
            .sorted { ($0.value, $1.key) > ($1.value, $0.key) }
            .map { (registry.name(for: $0.key), $0.value) }
    }

    /// Unresolved globals ranked by count, ties broken by FormID.
    var rankedUnresolvedGlobals: [(name: String, count: Int)] {
        unresolvedGlobals
            .sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
            .map { ($0.key.description, $0.value) }
    }

    /// Unresolved quests ranked by count, ties broken by FormID.
    var rankedUnresolvedQuests: [(name: String, count: Int)] {
        unresolvedQuests
            .sorted { ($0.value, $1.key.rawValue) > ($1.value, $0.key.rawValue) }
            .map { ($0.key.description, $0.value) }
    }

    /// Unsupported run-on buckets ranked by count, ties broken alphabetically.
    var rankedUnsupportedRunOns: [(name: String, count: Int)] {
        Self.ranked(unsupportedRunOns)
    }

    /// Unresolved-reference buckets ranked by count, ties broken alphabetically.
    var rankedUnresolvedReferences: [(name: String, count: Int)] {
        Self.ranked(unresolvedReferences)
    }

    private static func ranked(_ table: [String: Int]) -> [(name: String, count: Int)] {
        table
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { ($0.key, $0.value) }
    }

    /// Stable bucket name for a run-on type.
    static func runOnName(_ runOn: Condition.RunOnType) -> String {
        switch runOn {
        case .subject: "subject"
        case .target: "target"
        case .reference: "reference"
        case .combatTarget: "combatTarget"
        case .linkedReference: "linkedReference"
        case .questAlias: "questAlias"
        case .packageData: "packageData"
        case .eventData: "eventData"
        case let .unknown(raw): "unknown(\(raw))"
        }
    }
}
