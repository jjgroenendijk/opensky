// Dialogue selection: what a speaker has to say right now. It sits beside
// `WorldStateStore` rather than in it, because the store knows nothing about
// records. Inside a topic the first INFO in file order whose conditions pass wins.
// The selection rules are in docs/engine/dialogue.md.

import Foundation
import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState

/// Reads dialogue selection and writes said-state on top of a
/// `WorldStateStore`.
@MainActor
public struct DialogueRuntime: DialogueAccess {
    public let store: WorldStateStore
    /// Plugin-side index every selection reads and every mutation takes its
    /// session-stable keys from.
    public let dialogue: DialogueStore
    /// Quest state seam, so "is the owning quest running" is answered by the
    /// same resolution the condition functions read rather than by a second
    /// path into the store.
    public var questStates: QuestResolution
    /// Everything a condition may read. Selection overrides `subject`, `target`
    /// and `aliasQuest` per response and leaves the rest alone.
    public var context: ConditionContext
    public var registry: ConditionFunctionRegistry
    /// Where a chosen response's result scripts go. Nil in a session with no
    /// script runtime, in which case the fragments a response declares are
    /// counted as unrun rather than silently dropped.
    public var fragments: (any DialogueFragmentDispatching)?

    public init(
        store: WorldStateStore,
        dialogue: DialogueStore,
        questStates: QuestResolution = .empty,
        context: ConditionContext = ConditionContext(),
        registry: ConditionFunctionRegistry,
        fragments: (any DialogueFragmentDispatching)? = nil
    ) {
        self.store = store
        self.dialogue = dialogue
        self.questStates = questStates
        self.context = context
        self.registry = registry
        self.fragments = fragments
    }

    // MARK: - Said-state

    /// Said-state of one response: its runtime component when it has one, the
    /// unsaid baseline when it does not.
    public func saidState(of id: FormID) -> DialogueRuntimeState {
        guard let key = dialogue.key(forInfo: id) else { return .unsaid }
        return store.component(DialogueRuntimeState.self, for: key) ?? .unsaid
    }

    /// Whether the response has ever been said, which is what the say-once rule
    /// tests.
    public func hasBeenSaid(_ id: FormID) -> Bool {
        saidState(of: id).hasBeenSaid
    }

    /// Drops one response's said-state, so it reads from plugin data again. The
    /// component-level counterpart of `WorldStateStore.reset(_:)`.
    ///
    /// - Returns: true when runtime state was actually removed.
    @discardableResult
    public func reset(_ id: FormID) -> Bool {
        guard let key = dialogue.key(forInfo: id) else { return false }
        return store.reset(.dialogue, for: key)
    }

    // MARK: - Selection

    /// The topics `speaker` offers the player, plus those that offered nothing. Only
    /// DIAL category 0, the player's menu; other categories are spoken elsewhere.
    /// Branches scope the list: see `DialogueRuntimeBranches.swift`.
    public func topics(for speaker: ReferenceKey) -> DialogueSelection {
        let player = dialogue.sortedTopics().filter { $0.category == .player }
        if let blocking = blockingOffer(for: speaker) {
            let others = player.filter { $0.formID != blocking.offer.topic }
                .map { scopedOut($0, reason: .blockedByBranch(blocking.branch)) }
            return DialogueSelection(
                offers: [blocking.offer], rejected: others, tally: ConditionTally()
            )
        }
        let selection = selectTopics(player.filter(isBranchEntry), speaker: speaker)
        let scoped = player.filter { !isBranchEntry($0) }
            .map { scopedOut($0, reason: .notBranchEntry) }
        return DialogueSelection(
            offers: selection.offers,
            rejected: selection.rejected + scoped,
            tally: selection.tally
        )
    }

    /// The greeting `speaker` opens with, or nil. A blocking branch that answers
    /// greets with its starting topic. Otherwise greetings are the HELO subtype in
    /// DIAL SNAM; the highest-priority topic with a winning response wins, and ties
    /// go to FormID.
    public func greeting(for speaker: ReferenceKey) -> DialogueTopicOffer? {
        if let blocking = blockingOffer(for: speaker) {
            return blocking.offer
        }
        return selectTopics(
            dialogue.sortedTopics().filter { $0.subtype == "HELO" },
            speaker: speaker
        ).offers.first
    }

    /// Selection restricted to the topics `ids` names, which is what a chosen
    /// response's TCLT links produce.
    public func topics(linked ids: [FormID], speaker: ReferenceKey) -> DialogueSelection {
        selectTopics(ids.compactMap { dialogue.topic($0) }, speaker: speaker)
    }

    // MARK: - Private

    /// One pass over `topics`, ordered and traced. Every topic is evaluated, even after
    /// winners, so the tally can explain why an expected line did not appear.
    func selectTopics(_ topics: [DialogueTopic], speaker: ReferenceKey) -> DialogueSelection {
        var evaluator = ConditionEvaluator(
            context: context, registry: registry, tally: ConditionTally()
        )
        var offers: [DialogueTopicOffer] = []
        var rejected: [DialogueTopicOffer] = []
        for topic in ordered(topics) {
            let offer = consider(topic: topic, speaker: speaker, evaluator: &evaluator)
            if offer.considered.contains(where: \.isWinner) {
                offers.append(offer)
            } else {
                rejected.append(offer)
            }
        }
        return DialogueSelection(offers: offers, rejected: rejected, tally: evaluator.tally)
    }

    /// Descending priority, ascending FormID inside a priority. Sorted here
    /// rather than in the store because priority is a selection concern and the
    /// store is an index.
    private func ordered(_ topics: [DialogueTopic]) -> [DialogueTopic] {
        topics.sorted {
            $0.priority == $1.priority
                ? $0.formID.rawValue < $1.formID.rawValue
                : $0.priority > $1.priority
        }
    }

    /// Walks one topic's responses in file order and stops recording condition
    /// outcomes once one has won — the later entries are `.notReached`, which
    /// is a real outcome because file order *is* selection order.
    private func consider(
        topic: DialogueTopic,
        speaker: ReferenceKey,
        evaluator: inout ConditionEvaluator
    ) -> DialogueTopicOffer {
        let infos = dialogue.infos(for: topic.formID)
        guard isRunning(quest: topic.owningQuest) else {
            let reason = DialogueRejection.questNotRunning(topic.owningQuest ?? FormID(0))
            return DialogueTopicOffer(
                topic: topic.formID,
                info: infos.first?.formID ?? FormID(0),
                considered: infos.map {
                    DialogueInfoTrace(info: $0.formID, outcome: nil, rejection: reason)
                }
            )
        }
        var traces: [DialogueInfoTrace] = []
        var winner: FormID?
        for info in infos {
            let trace = winner == nil
                ? evaluate(info: info, topic: topic, speaker: speaker, evaluator: &evaluator)
                : DialogueInfoTrace(info: info.formID, outcome: nil, rejection: .notReached)
            if trace.isWinner {
                winner = info.formID
            }
            traces.append(trace)
        }
        return DialogueTopicOffer(
            topic: topic.formID,
            info: winner ?? infos.first?.formID ?? FormID(0),
            considered: traces
        )
    }

    /// One response: the say-once gate, the forced-speaker gate, then the
    /// condition list.
    private func evaluate(
        info: TopicInfo,
        topic: DialogueTopic,
        speaker: ReferenceKey,
        evaluator: inout ConditionEvaluator
    ) -> DialogueInfoTrace {
        if info.flags.contains(.sayOnce), hasBeenSaid(info.formID) {
            return DialogueInfoTrace(info: info.formID, outcome: nil, rejection: .alreadySaid)
        }
        if let forced = info.speaker, !speaks(speaker, as: forced) {
            return DialogueInfoTrace(
                info: info.formID, outcome: nil, rejection: .conditionsFailed
            )
        }
        // Only the per-response fields are written. Re-assigning the
        // whole context would reset the evaluator's random stream, and every
        // `GetRandomPercent` in one selection pass would then draw the same
        // number.
        evaluator.context.subject = speaker
        evaluator.context.target = .player
        evaluator.context.aliasQuest = topic.owningQuest
        evaluator.context.formIDTranslation = dialogue.translation(ofInfo: info.formID)
        let outcome = evaluator.evaluate(info.conditions)
        return DialogueInfoTrace(
            info: info.formID,
            outcome: outcome,
            rejection: outcome.isTrue ? nil : .conditionsFailed
        )
    }

    /// Whether the topic's owning quest is running. A topic naming no quest is
    /// always available, which is what an absent QNAM means.
    func isRunning(quest id: FormID?) -> Bool {
        guard let id else { return true }
        return questStates.state(for: id)?.isRunning ?? false
    }

    /// Whether `speaker` is a placement of the NPC_ record an INFO's ANAM names. A
    /// speaker with no indexed record passes, so it is not silenced for no reason.
    private func speaks(_ speaker: ReferenceKey, as forced: FormID) -> Bool {
        guard let entry = context.references[speaker] else { return true }
        return ConditionFunctions.baseForm(of: entry) == forced
    }
}
