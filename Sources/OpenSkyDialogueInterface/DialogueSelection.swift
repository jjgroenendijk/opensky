// What dialogue selection produced, and why: the offered topics, the winning
// response in each, and the reason every other response lost. The acceptance
// panel needs the trace, so selection keeps every `ConditionOutcome`.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

/// Why one response was not chosen.
///
/// Ordered by when the check happens, which is also the order the reasons are
/// worth reading in: a response whose topic's quest is not running was never a
/// candidate, while one whose conditions failed was.
nonisolated public enum DialogueRejection: Equatable, Sendable {
    /// The topic names an owning quest that is not running.
    case questNotRunning(FormID)
    /// The response is flagged say-once and has already been said.
    case alreadySaid
    /// The response was said fewer game hours ago than its reset time.
    case waitingForReset
    /// The response's condition list evaluated false.
    case conditionsFailed
    /// The topic is not the starting topic of a top-level branch, so only a
    /// link from a chosen response reaches it.
    case notBranchEntry
    /// A blocking or exclusive branch answers, so its starting topic is the only
    /// topic offered. Carries that branch.
    case blockedByBranch(FormID)
    /// An earlier response in file order already won, so this one was never
    /// evaluated. File order is selection order, so this is a real outcome
    /// rather than a missing one.
    case notReached
}

/// One response considered for a topic, with the reason it did or did not win.
nonisolated public struct DialogueInfoTrace: Equatable, Sendable {
    /// The INFO record considered.
    public let info: FormID
    /// Its condition list's outcome, or nil when the response was rejected
    /// before its conditions were reached — a say-once line already said, or a
    /// line after the winner.
    public let outcome: ConditionOutcome?
    /// Nil for the winner, and the reason otherwise.
    public let rejection: DialogueRejection?

    public var isWinner: Bool {
        rejection == nil
    }

    public init(info: FormID, outcome: ConditionOutcome?, rejection: DialogueRejection?) {
        self.info = info
        self.outcome = outcome
        self.rejection = rejection
    }
}

/// One topic a speaker offers, with the response that won it.
nonisolated public struct DialogueTopicOffer: Equatable, Sendable {
    /// The DIAL record.
    public let topic: FormID
    /// The INFO that won, in the file order the child group lists.
    public let info: FormID
    /// Every response considered for this topic, in file order, winner
    /// included.
    public let considered: [DialogueInfoTrace]

    /// Reasons every considered response could not be answered cleanly, in
    /// evaluation order. Empty when the whole topic evaluated from real
    /// answers, which is what makes coverage measurable rather than assumed.
    public var failures: [ConditionFailure] {
        considered.flatMap { $0.outcome?.failures ?? [] }
    }

    public init(topic: FormID, info: FormID, considered: [DialogueInfoTrace]) {
        self.topic = topic
        self.info = info
        self.considered = considered
    }
}

/// The result of asking what a speaker has to say.
nonisolated public struct DialogueSelection: Equatable, Sendable {
    /// Topics the player may pick, in the order they should be listed:
    /// descending DIAL priority, then ascending FormID.
    public let offers: [DialogueTopicOffer]
    /// Topics that were considered and offered nothing, with the reason each
    /// of their responses lost. Kept rather than dropped because "this topic
    /// exists and offered nothing" is what an acceptance readout has to
    /// explain.
    public let rejected: [DialogueTopicOffer]
    /// What the condition evaluator could not answer while selecting.
    public let tally: ConditionTally

    public static let empty = DialogueSelection(offers: [], rejected: [], tally: ConditionTally())

    public init(
        offers: [DialogueTopicOffer],
        rejected: [DialogueTopicOffer],
        tally: ConditionTally
    ) {
        self.offers = offers
        self.rejected = rejected
        self.tally = tally
    }
}

/// What choosing a response produced.
nonisolated public struct DialogueChoice: Equatable, Sendable {
    /// Topics the chosen response links to through TCLT, filtered the same way
    /// the offered list is, so a link to a topic whose quest has since stopped
    /// does not appear.
    public let next: DialogueSelection
    /// Whether the response ends the conversation, which is the documented
    /// meaning of the goodbye flag.
    public let endsConversation: Bool
    /// Result-script fragments that were dispatched, in begin-then-end order.
    /// Empty when the response carries no result script, and also when no
    /// dispatcher was wired — the two are distinguished by
    /// `unrunFragmentCount`.
    public let dispatchedFragments: [String]
    /// Fragments the response declared that nothing ran. Counted rather than
    /// dropped: a result script that never runs is exactly the gap this number
    /// exists to surface.
    public let unrunFragmentCount: Int

    public init(
        next: DialogueSelection,
        endsConversation: Bool,
        dispatchedFragments: [String],
        unrunFragmentCount: Int
    ) {
        self.next = next
        self.endsConversation = endsConversation
        self.dispatchedFragments = dispatchedFragments
        self.unrunFragmentCount = unrunFragmentCount
    }
}
