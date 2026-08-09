// What dialogue selection produced, and why (issue #426, roadmap item 17.2).
//
// The types here are the *answer* half of `DialogueRuntime`: which topics a
// speaker offers, which response won inside each, and — for every response that
// did not win — the reason it lost. They are separate from the runtime for the
// reason `ConditionContext` is separate from `ConditionEvaluator`: a caller
// rendering a topic menu or an acceptance readout needs these and nothing else,
// while a caller changing how selection works needs the other file.
//
// The trace is not a debugging afterthought. Item 17.8's acceptance panel has
// to show why a line was or was not offered, and `ConditionOutcome.failures`
// already carries the machine-readable reasons, so selection keeps every
// outcome it computed instead of reducing the work to a Bool and throwing the
// evidence away.

import Foundation

/// Why one response was not chosen.
///
/// Ordered by when the check happens, which is also the order the reasons are
/// worth reading in: a response whose topic's quest is not running was never a
/// candidate, while one whose conditions failed was.
nonisolated enum DialogueRejection: Equatable, Sendable {
    /// The topic names an owning quest that is not running.
    case questNotRunning(FormID)
    /// The response is flagged say-once and has already been said.
    case alreadySaid
    /// The response's condition list evaluated false.
    case conditionsFailed
    /// An earlier response in file order already won, so this one was never
    /// evaluated. File order is selection order, so this is a real outcome
    /// rather than a missing one.
    case notReached
}

/// One response considered for a topic, with the reason it did or did not win.
nonisolated struct DialogueInfoTrace: Equatable, Sendable {
    /// The INFO record considered.
    let info: FormID
    /// Its condition list's outcome, or nil when the response was rejected
    /// before its conditions were reached — a say-once line already said, or a
    /// line after the winner.
    let outcome: ConditionOutcome?
    /// Nil for the winner, and the reason otherwise.
    let rejection: DialogueRejection?

    var isWinner: Bool {
        rejection == nil
    }
}

/// One topic a speaker offers, with the response that won it.
nonisolated struct DialogueTopicOffer: Equatable, Sendable {
    /// The DIAL record.
    let topic: FormID
    /// The INFO that won, in the file order the child group lists.
    let info: FormID
    /// Every response considered for this topic, in file order, winner
    /// included.
    let considered: [DialogueInfoTrace]

    /// Reasons every considered response could not be answered cleanly, in
    /// evaluation order. Empty when the whole topic evaluated from real
    /// answers, which is what makes coverage measurable rather than assumed.
    var failures: [ConditionFailure] {
        considered.flatMap { $0.outcome?.failures ?? [] }
    }
}

/// The result of asking what a speaker has to say.
nonisolated struct DialogueSelection: Equatable, Sendable {
    /// Topics the player may pick, in the order they should be listed:
    /// descending DIAL priority, then ascending FormID.
    let offers: [DialogueTopicOffer]
    /// Topics that were considered and offered nothing, with the reason each
    /// of their responses lost. Kept rather than dropped because "this topic
    /// exists and offered nothing" is what an acceptance readout has to
    /// explain.
    let rejected: [DialogueTopicOffer]
    /// What the condition evaluator could not answer while selecting.
    let tally: ConditionTally

    static let empty = DialogueSelection(offers: [], rejected: [], tally: ConditionTally())

    var isEmpty: Bool {
        offers.isEmpty
    }
}

/// What choosing a response produced.
nonisolated struct DialogueChoice: Equatable, Sendable {
    /// The response that was chosen.
    let info: FormID
    /// Said-state as stored afterwards.
    let state: DialogueRuntimeState
    /// Topics the chosen response links to through TCLT, filtered the same way
    /// the offered list is, so a link to a topic whose quest has since stopped
    /// does not appear.
    let next: DialogueSelection
    /// Whether the response ends the conversation, which is the documented
    /// meaning of the goodbye flag.
    let endsConversation: Bool
    /// Result-script fragments that were dispatched, in begin-then-end order.
    /// Empty when the response carries no result script, and also when no
    /// dispatcher was wired — the two are distinguished by
    /// `unrunFragmentCount`.
    let dispatchedFragments: [String]
    /// Fragments the response declared that nothing ran. Counted rather than
    /// dropped: a result script that never runs is exactly the gap this number
    /// exists to surface.
    let unrunFragmentCount: Int
}
