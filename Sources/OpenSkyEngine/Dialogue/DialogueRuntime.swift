// Dialogue selection (issue #426, roadmap item 17.2): the layer that answers
// "what does this speaker have to say right now?".
//
// A thin layer beside `WorldStateStore` rather than methods on it, following
// the `QuestRuntime` precedent this issue names. The store is the generic
// substrate that knows about keys, components, journalling and snapshots and
// deliberately knows nothing about records; dialogue needs `DialogueStore` for
// the records and for the session-stable key said-state is filed under,
// `QuestStore` for the quest a topic belongs to, and a `ConditionContext` for
// everything a CTDA may read. None of those belong inside the store.
//
// Headless and AppKit-free: this compiles into `openskycli` and is testable
// without a window. `@MainActor` only because the store it writes to is. No
// audio, no camera, no menu — item 17.8's panel and the voice work above it sit
// on top of this, and nothing here knows they exist.
//
// ## The selection rules, and where each comes from
//
// * A topic belongs to a quest (DIAL QNAM) and is only offered while that quest
//   runs. Every one of the 15,037 DIAL records in `Skyrim.esm` names one, so
//   this is the primary filter rather than an edge case. The Creation Kit's
//   dialogue documentation states the rule plainly: "Dialogue is organized by
//   quest" and a topic's lines are available when its quest is running
//   (<https://ck.uesp.net/wiki/Dialogue_Views>).
// * Inside a topic the INFO records are evaluated in file order and the first
//   one whose conditions pass wins. That is why `DialogueStore` preserves the
//   order of the type-7 child group rather than sorting it, and why this file
//   never re-orders `infos(for:)`.
// * A response flagged say-once that has already been said is skipped before
//   its conditions are evaluated. "Say Once: If checked, this info will only be
//   said once. Once said, it will never be said again."
//   (<https://ck.uesp.net/wiki/Dialogue_Views>, Response Data.)
// * A response whose ANAM names a speaker other than this one is skipped. ANAM
//   is the forced-speaker link, carried by 223 of `Skyrim.esm`'s 31,465 INFOs.
// * The offered topics are ordered by DIAL PNAM priority, descending, and by
//   FormID within a priority so the list is deterministic. Priority is what the
//   field is called and what it is for; the FormID tie-break is OpenSky's,
//   because the Creation Kit documents no order between equal priorities and a
//   dictionary order would make the same world produce two different menus.
//
// ## What this deliberately does not do
//
// Scenes (SCEN) are not played: the M17 gate is satisfied by a conversation,
// and 17.1's sweep found 7,426 DIAL records in the scene category that belong
// to that separate machinery. Shared responses (INFO DNAM) replace another
// record's *response data* and therefore change what a chosen line says rather
// than whether it is offered, so they are a concern of the text layer above.
// Neither is missing by accident; see docs/engine/dialogue.md.
//
// Documented in docs/engine/dialogue.md.

import Foundation

/// Reads dialogue selection and writes said-state on top of a
/// `WorldStateStore`.
@MainActor
struct DialogueRuntime {
    let store: WorldStateStore
    /// Plugin-side index every selection reads and every mutation takes its
    /// session-stable keys from.
    let dialogue: DialogueStore
    /// Quest index, for the owning-quest filter and for the alias scope a
    /// dialogue condition is evaluated in.
    let quests: QuestStore
    /// Quest state seam, so "is the owning quest running" is answered by the
    /// same resolution the condition functions read rather than by a second
    /// path into the store.
    var questStates: QuestResolution
    /// Everything a condition may read. Selection overrides `subject`, `target`
    /// and `aliasQuest` per response and leaves the rest alone.
    var context: ConditionContext
    var registry: ConditionFunctionRegistry
    /// Where a chosen response's result scripts go. Nil in a session with no
    /// script runtime, in which case the fragments a response declares are
    /// counted as unrun rather than silently dropped.
    var fragments: (any DialogueFragmentDispatching)?

    init(
        store: WorldStateStore,
        dialogue: DialogueStore,
        quests: QuestStore,
        questStates: QuestResolution = .empty,
        context: ConditionContext = ConditionContext(),
        registry: ConditionFunctionRegistry = .standard,
        fragments: (any DialogueFragmentDispatching)? = nil
    ) {
        self.store = store
        self.dialogue = dialogue
        self.quests = quests
        self.questStates = questStates
        self.context = context
        self.registry = registry
        self.fragments = fragments
    }

    // MARK: - Said-state

    /// Said-state of one response: its runtime component when it has one, the
    /// unsaid baseline when it does not.
    func saidState(of id: FormID) -> DialogueRuntimeState {
        guard let key = dialogue.key(forInfo: id) else { return .unsaid }
        return store.component(DialogueRuntimeState.self, for: key) ?? .unsaid
    }

    /// Whether the response has ever been said, which is what the say-once rule
    /// tests.
    func hasBeenSaid(_ id: FormID) -> Bool {
        saidState(of: id).hasBeenSaid
    }

    /// Drops one response's said-state, so it reads from plugin data again. The
    /// component-level counterpart of `WorldStateStore.reset(_:)`.
    ///
    /// - Returns: true when runtime state was actually removed.
    @discardableResult
    func reset(_ id: FormID) -> Bool {
        guard let key = dialogue.key(forInfo: id) else { return false }
        return store.reset(.dialogue, for: key)
    }

    // MARK: - Selection

    /// The topics `speaker` offers the player, plus the ones that were
    /// considered and offered nothing.
    ///
    /// Player-facing topics only: DIAL DATA's category names what a topic is
    /// for, and only category 0 is the menu the player picks from. The other
    /// categories — scene, combat, detection and the rest — are spoken by the
    /// machinery that owns them and never appear as a choice.
    func topics(for speaker: ReferenceKey) -> DialogueSelection {
        select(
            topics: dialogue.sortedTopics().filter { $0.category == .player },
            speaker: speaker
        )
    }

    /// The greeting `speaker` opens with, or nil when no greeting applies.
    ///
    /// Greetings are the HELO subtype rather than a category of their own: DIAL
    /// SNAM is the authoritative four-character subtype (see `DialogueTopic`),
    /// and `Skyrim.esm` carries 297 HELO topics. The highest-priority topic
    /// with a winning response is the greeting; ties fall to FormID, exactly as
    /// in the offered list.
    func greeting(for speaker: ReferenceKey) -> DialogueTopicOffer? {
        select(
            topics: dialogue.sortedTopics().filter { $0.subtype == "HELO" },
            speaker: speaker
        ).offers.first
    }

    /// Selection restricted to the topics `ids` names, which is what a chosen
    /// response's TCLT links produce.
    func topics(linked ids: [FormID], speaker: ReferenceKey) -> DialogueSelection {
        select(topics: ids.compactMap { dialogue.topic($0) }, speaker: speaker)
    }

    // MARK: - Private

    /// One pass over `topics`, ordered and traced.
    ///
    /// Every topic is evaluated even once several have won, because the tally
    /// and the rejected list are results in their own right: item 17.8 has to
    /// explain why a line the player expected did not appear, and a
    /// short-circuit would leave exactly that case unexplained.
    private func select(topics: [DialogueTopic], speaker: ReferenceKey) -> DialogueSelection {
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
        // Only the three per-response fields are written. Re-assigning the
        // whole context would reset the evaluator's random stream, and every
        // `GetRandomPercent` in one selection pass would then draw the same
        // number.
        evaluator.context.subject = speaker
        evaluator.context.target = .player
        evaluator.context.aliasQuest = topic.owningQuest
        let outcome = evaluator.evaluate(info.conditions)
        return DialogueInfoTrace(
            info: info.formID,
            outcome: outcome,
            rejection: outcome.isTrue ? nil : .conditionsFailed
        )
    }

    /// Whether the topic's owning quest is running. A topic naming no quest is
    /// always available, which is what an absent QNAM means.
    private func isRunning(quest id: FormID?) -> Bool {
        guard let id else { return true }
        return questStates.state(for: id)?.isRunning ?? false
    }

    /// Whether `speaker` is a placement of the NPC_ record an INFO's ANAM
    /// names.
    ///
    /// A speaker the reference index holds no record for cannot be compared, so
    /// the gate passes rather than failing: refusing every response of an actor
    /// this session has not indexed would silence a speaker for a reason that
    /// has nothing to do with the record.
    private func speaks(_ speaker: ReferenceKey, as forced: FormID) -> Bool {
        guard let entry = context.references[speaker] else { return true }
        return ConditionFunctions.baseForm(of: entry) == forced
    }
}
