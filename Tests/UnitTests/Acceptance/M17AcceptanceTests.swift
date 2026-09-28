// M17 acceptance (issue #209): one conversation, from the use key to the save.
//
// The gate statement in one run: pressing the use key on a voiced actor opens
// the vanilla menu without pausing the world, the list holds the topics whose
// conditions pass and not the one whose condition does not, choosing a response
// runs its result script, the result advances an M13 quest stage, the stage
// makes a new topic appear in the same conversation, the say-once line drops
// out, goodbye ends it, leaving hands the menu stack back, and everything the
// conversation wrote survives a save and a load.
//
// Every step drives a shipping entry point — the streamer's Talk activation and
// the `DialogueControlProviding` members the panel buttons and the live keys
// both call — and asserts an engine model at the far end. The panel half is
// `M17AcceptancePanelTests`, the budget half is `M17AcceptanceBudgetTests`, the
// pixel half is `M17AcceptanceRenderTests` and the vanilla half is
// `M17AcceptanceRealDataTests`; the last two are gated, and everything here runs
// on a device-less runner with no install.

import Foundation
@testable import opensky
import Testing

@MainActor
struct M17AcceptanceTests {
    /// The gate itself. One conversation, checked at every step so a failure
    /// names the step rather than leaving an end state to reverse-engineer.
    @Test("one conversation opens, advances a quest, and survives a save")
    func theRouteRunsTheWholeM17Loop() throws {
        let chain = try M17AcceptanceChain()

        try Self.theUseKeyOpensTheConversation(chain)
        try Self.theListIsConditionFiltered(chain)
        try Self.choosingAResponseAdvancesTheQuest(chain)
        try Self.theQuestStageChangesWhatIsOffered(chain)
        try Self.goodbyeEndsTheConversation(chain)
        try Self.theSaidStateSurvivesASaveAndLoad(chain)
        try Self.asecondConversationOpensOnWhatTheFirstLeftBehind(chain)
    }

    // MARK: - The route

    /// Step 1 — the use key. The view ray picks the actor, the streamer
    /// publishes one activation, the menu opens on it with the greeting being
    /// said, and — the thing that makes this menu different from every other
    /// one in the engine — the world keeps simulating behind it.
    private static func theUseKeyOpensTheConversation(_ chain: M17AcceptanceChain) throws {
        #expect(!chain.snapshot.isOpen)
        let speaker = try chain.pressUseKeyOnTheSpeaker()

        #expect(speaker == M17AcceptanceFixture.speakerKey)
        #expect(chain.activations.map(\.speaker) == [M17AcceptanceFixture.speakerKey])
        #expect(chain.snapshot.isOpen)
        #expect(chain.model.speakerKey == M17AcceptanceFixture.speakerKey)
        #expect(chain.model.state == .greeting)
        #expect(chain.model.subtitle == "Well met, traveller.")
        #expect(chain.snapshot.openMenus.contains("Dialogue Menu"))
        #expect(!chain.snapshot.worldSimPaused, "the dialogue menu must leave the world running")
        // A greeting is a delivered response, so it spends its say-once flag
        // the moment it is said rather than when the conversation ends.
        #expect(chain.saidCount(of: M17AcceptanceFixture.greetingInfo) == 1)
    }

    /// Step 2 — the list. Saying the greeting to its end hands the topic list
    /// back, and what is in it is what the conditions decided: the quest topic
    /// and the goodbye, but not the topic gated on a stage nobody has reached.
    /// The rejection is in the trace with its reason, which is what makes an
    /// absent topic explainable rather than mysterious.
    private static func theListIsConditionFiltered(_ chain: M17AcceptanceChain) throws {
        chain.finishTheLine()
        #expect(chain.model.state == .topicList)
        #expect(chain.topicTexts == ["I will help you.", "Farewell."])

        let rejected = try #require(chain.snapshot.rejections.first {
            $0.topic == FormID(M17AcceptanceFixture.stageTopic)
        })
        #expect(rejected.reasons.contains { $0.contains("conditions") })
        #expect(chain.snapshot.unresolvedConditionCount == 0, "every condition resolved")
    }

    /// Step 3 — the choice. Choosing the topic says its response, and its
    /// generated result script runs on the Papyrus VM and sets a stage on the
    /// M13 quest runtime. Nothing in the dialogue layer knows what a stage is:
    /// the stage is asserted through `QuestRuntime`, which never heard of a
    /// conversation.
    private static func choosingAResponseAdvancesTheQuest(_ chain: M17AcceptanceChain) throws {
        #expect(try !chain.questState().isStageDone(PapyrusQuestFixture.fragmentStage))

        try chain.chooseTopic(named: "I will help you.")
        #expect(chain.model.state == .response)
        #expect(chain.model.subtitle == "Then it is begun.")
        #expect(chain.saidCount(of: M17AcceptanceFixture.questInfo) == 1)

        chain.drainScripts()
        #expect(try chain.questState().isStageDone(PapyrusQuestFixture.fragmentStage))
        #expect(try chain.questState().isRunning)
    }

    /// Step 4 — the loop closing. Handing the list back re-selects it against
    /// the world the response just changed, so the stage-gated topic is now
    /// offered and the say-once line that set the stage is gone. The player
    /// sees the quest advance without opening the journal.
    private static func theQuestStageChangesWhatIsOffered(_ chain: M17AcceptanceChain) throws {
        chain.finishTheLine()
        #expect(chain.model.state == .topicList)
        #expect(chain.topicTexts == ["About what you asked of me.", "Farewell."])
        #expect(
            !chain.topicTexts.contains("I will help you."),
            "a say-once line stayed on offer after being said"
        )
    }

    /// Step 5 — the exit. A goodbye response ends the conversation when it
    /// finishes rather than needing a second key, the menu stack is handed
    /// back, and the subtitle does not survive the menu it was said in.
    private static func goodbyeEndsTheConversation(_ chain: M17AcceptanceChain) throws {
        try chain.chooseTopic(named: "Farewell.")
        #expect(chain.model.state == .response)
        #expect(chain.model.subtitle == "Safe roads.")

        chain.finishTheLine()
        #expect(!chain.snapshot.isOpen, "goodbye did not close the conversation")
        #expect(!chain.snapshot.openMenus.contains("Dialogue Menu"))
        #expect(chain.snapshot.subtitle == nil)
        #expect(chain.saidCount(of: M17AcceptanceFixture.goodbyeInfo) == 1)
    }

    /// Step 6 — persistence. Everything the conversation wrote is world state
    /// like any other, so it goes through the same encoder and decoder a save
    /// does, and comes back naming the same responses and the same stage.
    private static func theSaidStateSurvivesASaveAndLoad(_ chain: M17AcceptanceChain) throws {
        let restored = try chain.roundTripThroughASave()

        for info in [
            M17AcceptanceFixture.greetingInfo,
            M17AcceptanceFixture.questInfo,
            M17AcceptanceFixture.goodbyeInfo
        ] {
            let state = try #require(restored.component(
                DialogueRuntimeState.self, for: M17AcceptanceFixture.infoKey(info)
            ))
            #expect(state.hasBeenSaid, "INFO \(String(info, radix: 16)) came back unsaid")
        }
        let quests = try QuestRuntime(
            store: restored, quests: PapyrusQuestFixture.store(PapyrusQuestFixture.quest())
        )
        #expect(try quests.state(of: PapyrusQuestFixture.questFormID)
            .isStageDone(PapyrusQuestFixture.fragmentStage))
    }

    /// Step 7 — the state is not just stored, it is read back. Talking to the
    /// same actor again opens on the list the first conversation left behind:
    /// no greeting, because the greeting was say-once, and the stage-gated
    /// topic still on offer because the stage is still done.
    private static func asecondConversationOpensOnWhatTheFirstLeftBehind(
        _ chain: M17AcceptanceChain
    ) throws {
        chain.openDialogue()
        #expect(chain.snapshot.isOpen)
        #expect(chain.model.state == .topicList, "a spent greeting was said again")
        #expect(chain.topicTexts == ["About what you asked of me.", "Farewell."])

        chain.leaveDialogue()
        #expect(!chain.snapshot.isOpen)
        #expect(chain.snapshot.openMenus.isEmpty, "leaving left a menu on the stack")
    }
}
