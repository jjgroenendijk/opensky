// Dialogue selection and choice flow (issue #426, roadmap item 17.2), over the
// synthetic world in `DialogueRuntimeFixture`.
//
// Every property here is one of the documented selection rules rather than a
// restatement of the implementation: the owning-quest gate, file order as
// selection order, say-once, priority ordering, and what choosing a response
// does to said-state and to the follow-up topics.

import Foundation
@testable import opensky
import Testing

@MainActor
struct DialogueRuntimeTests {
    // MARK: - Offered topics

    /// The player-facing topics whose quest runs and whose responses pass, in
    /// priority order. The scene topic and the dormant quest's topic are both
    /// absent, for two different reasons.
    @Test func offersRunningPlayerTopicsInPriorityOrder() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let selection = runtime.topics(for: DialogueRuntimeFixture.speakerKey)

        #expect(selection.offers.map(\.topic.rawValue) == [
            DialogueRuntimeFixture.urgentTopic,
            DialogueRuntimeFixture.ordinaryTopic
        ])
        #expect(selection.offers.map(\.info.rawValue) == [
            DialogueRuntimeFixture.urgentFirstInfo,
            DialogueRuntimeFixture.ordinaryInfo
        ])
    }

    /// A topic whose owning quest is not running offers nothing, and says so
    /// with the quest's FormID rather than with a generic failure.
    @Test func aTopicOfADormantQuestIsRejectedByItsQuest() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let selection = runtime.topics(for: DialogueRuntimeFixture.speakerKey)
        let gated = try #require(selection.rejected.first {
            $0.topic.rawValue == DialogueRuntimeFixture.gatedTopic
        })
        #expect(gated.considered.map(\.rejection) == [
            .questNotRunning(FormID(DialogueRuntimeFixture.dormantQuest))
        ])
    }

    /// A scene topic is not a player choice however its conditions evaluate, so
    /// it is not even considered.
    @Test func sceneTopicsAreNeverConsidered() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let selection = runtime.topics(for: DialogueRuntimeFixture.speakerKey)
        let all = selection.offers + selection.rejected
        #expect(!all.contains { $0.topic.rawValue == DialogueRuntimeFixture.sceneTopic })
    }

    /// Inside a topic the first response in file order whose conditions pass
    /// wins, the failing one before it is recorded as such, and the ones after
    /// the winner are never evaluated.
    @Test func fileOrderIsSelectionOrder() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let offer = try #require(runtime.topics(for: DialogueRuntimeFixture.speakerKey)
            .offers.first { $0.topic.rawValue == DialogueRuntimeFixture.ordinaryTopic })

        #expect(offer.considered.map(\.info.rawValue) == [
            DialogueRuntimeFixture.ordinaryWrongSpeakerInfo,
            DialogueRuntimeFixture.ordinaryInfo,
            DialogueRuntimeFixture.ordinaryUnreachedInfo
        ])
        #expect(offer.considered.map(\.rejection) == [
            .conditionsFailed, nil, .notReached
        ])
        // The loser was evaluated and the unreached one was not, which is what
        // makes the trace usable as an explanation.
        #expect(offer.considered[0].outcome?.isTrue == false)
        #expect(offer.considered[2].outcome == nil)
        #expect(offer.failures.isEmpty)
    }

    /// The greeting is selected by HELO subtype rather than by category, so it
    /// answers even though its topic is not a player choice.
    @Test func greetingComesFromTheHeloSubtype() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let greeting = try #require(runtime.greeting(for: DialogueRuntimeFixture.speakerKey))
        #expect(greeting.topic.rawValue == DialogueRuntimeFixture.greetingTopic)
        #expect(greeting.info.rawValue == DialogueRuntimeFixture.greetingInfo)
    }

    /// Selection is per speaker, not per world. A second actor is offered only
    /// the response whose conditions name *it*, and gets no greeting at all
    /// because the greeting names the first speaker.
    @Test func adifferentSpeakerGetsADifferentList() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let stranger = ConditionEvaluatorFixture.key(ConditionEvaluatorFixture.targetFormID)
        let selection = runtime.topics(for: stranger)
        #expect(selection.offers.map(\.topic.rawValue)
            == [DialogueRuntimeFixture.ordinaryTopic])
        #expect(selection.offers.first?.info.rawValue
            == DialogueRuntimeFixture.ordinaryWrongSpeakerInfo)
        #expect(runtime.greeting(for: stranger) == nil)
    }

    // MARK: - Say once

    /// A say-once response drops out after it has been said, and the topic
    /// falls through to the next response in file order rather than
    /// disappearing.
    @Test func aSayOnceResponseIsSkippedOnceSaid() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        try runtime.choose(
            FormID(DialogueRuntimeFixture.urgentFirstInfo),
            speaker: DialogueRuntimeFixture.speakerKey
        )

        let offer = try #require(runtime.topics(for: DialogueRuntimeFixture.speakerKey)
            .offers.first { $0.topic.rawValue == DialogueRuntimeFixture.urgentTopic })
        #expect(offer.info.rawValue == DialogueRuntimeFixture.urgentSecondInfo)
        #expect(offer.considered.first?.rejection == .alreadySaid)
        // The say-once gate runs before the conditions, so the spent response
        // carries no outcome at all.
        #expect(offer.considered.first?.outcome == nil)
    }

    /// A response with no say-once flag is offered again after being said, and
    /// the count keeps rising.
    @Test func aRepeatableResponseStaysOnOffer() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        for _ in 0 ..< 3 {
            try runtime.choose(
                FormID(DialogueRuntimeFixture.ordinaryInfo),
                speaker: DialogueRuntimeFixture.speakerKey
            )
        }
        #expect(runtime.saidState(of: FormID(DialogueRuntimeFixture.ordinaryInfo))
            .saidCount == 3)
        let offer = try #require(runtime.topics(for: DialogueRuntimeFixture.speakerKey)
            .offers.first { $0.topic.rawValue == DialogueRuntimeFixture.ordinaryTopic })
        #expect(offer.info.rawValue == DialogueRuntimeFixture.ordinaryInfo)
    }

    /// Said-state is world state like any other: it lands in the store under
    /// the INFO's session-stable key, and resetting it puts the response back.
    @Test func saidStateIsStoredUnderTheInfoKeyAndResets() throws {
        let store = WorldStateStore()
        let runtime = try DialogueRuntimeFixture.runtime(store: store)
        let id = FormID(DialogueRuntimeFixture.urgentFirstInfo)
        try runtime.choose(id, speaker: DialogueRuntimeFixture.speakerKey)

        let key = DialogueRuntimeFixture.infoKey(DialogueRuntimeFixture.urgentFirstInfo)
        #expect(store.component(DialogueRuntimeState.self, for: key)?.saidCount == 1)
        #expect(runtime.hasBeenSaid(id))
        #expect(runtime.reset(id))
        #expect(!runtime.hasBeenSaid(id))
        #expect(store.component(DialogueRuntimeState.self, for: key) == nil)
    }

    // MARK: - Choice flow

    /// Choosing a response returns the topics it links to, filtered by the same
    /// rules the offered list uses.
    @Test func choosingFollowsTopicLinks() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let choice = try runtime.choose(
            FormID(DialogueRuntimeFixture.ordinaryInfo),
            speaker: DialogueRuntimeFixture.speakerKey
        )
        #expect(choice.next.offers.map(\.topic.rawValue)
            == [DialogueRuntimeFixture.urgentTopic])
        #expect(!choice.endsConversation)
    }

    /// A response no plugin declares is a typed failure that writes nothing,
    /// rather than a silently ignored choice.
    @Test func choosingAnUnknownResponseThrows() throws {
        let store = WorldStateStore()
        let runtime = try DialogueRuntimeFixture.runtime(store: store)
        #expect(throws: DialogueError.unknownInfo(FormID(0xDEAD))) {
            try runtime.choose(FormID(0xDEAD), speaker: DialogueRuntimeFixture.speakerKey)
        }
        #expect(store.dirtyCount == 0)
    }

    /// With no dispatcher wired, a response's result fragments are counted as
    /// unrun rather than dropped: a result script that never runs is a gap the
    /// caller has to be able to see.
    @Test func fragmentsWithNoDispatcherAreCountedUnrun() throws {
        let runtime = try DialogueRuntimeFixture.runtime()
        let choice = try runtime.choose(
            FormID(DialogueRuntimeFixture.ordinaryInfo),
            speaker: DialogueRuntimeFixture.speakerKey
        )
        #expect(choice.dispatchedFragments.isEmpty)
        #expect(choice.unrunFragmentCount == 2)
    }

    /// Both result boxes are dispatched, begin before end, and a response with
    /// no result script dispatches nothing.
    @Test func bothResultFragmentsAreDispatchedInPhaseOrder() throws {
        let dispatcher = RecordingDialogueDispatcher()
        let runtime = try DialogueRuntimeFixture.runtime(fragments: dispatcher)

        let choice = try runtime.choose(
            FormID(DialogueRuntimeFixture.ordinaryInfo),
            speaker: DialogueRuntimeFixture.speakerKey
        )
        #expect(dispatcher.phases == [.begin, .end])
        #expect(choice.dispatchedFragments == [
            DialogueRuntimeFixture.beginFunction, DialogueRuntimeFixture.endFunction
        ])
        #expect(choice.unrunFragmentCount == 0)

        try runtime.choose(
            FormID(DialogueRuntimeFixture.urgentSecondInfo),
            speaker: DialogueRuntimeFixture.speakerKey
        )
        #expect(dispatcher.phases == [.begin, .end])
    }

    /// Said-state is written before the result runs, so a result script that
    /// re-enters selection cannot be offered the line it is running.
    @Test func saidStateIsWrittenBeforeTheResultRuns() throws {
        let store = WorldStateStore()
        let dispatcher = RecordingDialogueDispatcher()
        let runtime = try DialogueRuntimeFixture.runtime(store: store, fragments: dispatcher)
        dispatcher.onDispatch = { [store] key in
            store.component(DialogueRuntimeState.self, for: key)?.saidCount ?? 0
        }
        try runtime.choose(
            FormID(DialogueRuntimeFixture.ordinaryInfo),
            speaker: DialogueRuntimeFixture.speakerKey
        )
        #expect(dispatcher.observedCounts == [1, 1])
    }
}

/// A dispatcher that records what it was asked to run and answers with the
/// fragment's own function name, so a test can assert both the order and the
/// state visible while it runs.
@MainActor
final class RecordingDialogueDispatcher: DialogueFragmentDispatching {
    private(set) var phases: [TopicInfoFragmentPhase] = []
    private(set) var observedCounts: [UInt32] = []
    var onDispatch: ((ReferenceKey) -> UInt32)?

    func runTopicInfoFragments(
        of info: TopicInfo,
        key: ReferenceKey,
        phase: TopicInfoFragmentPhase
    ) -> [String] {
        phases.append(phase)
        if let onDispatch {
            observedCounts.append(onDispatch(key))
        }
        guard let fragment = info.script.infoFragments?.fragment(phase) else { return [] }
        return [fragment.functionName]
    }
}
