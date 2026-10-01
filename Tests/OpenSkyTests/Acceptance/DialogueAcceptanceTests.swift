// Dialogue acceptance: use key opens the menu without pausing; failing topics
// are hidden; a result script advances a quest stage that adds a topic;
// say-once drops out; goodbye ends it; state survives save and load. Each step
// uses a shipping entry point. Pixel and real-data halves are gated.

import Foundation
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyMenus
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct DialogueAcceptanceTests {
    /// The gate itself. One conversation, checked at every step so a failure
    /// names the step rather than leaving an end state to reverse-engineer.
    @Test("one conversation opens, advances a quest, and survives a save")
    func theRouteRunsTheWholeM17Loop() throws {
        let chain = try DialogueAcceptanceChain()

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
    private static func theUseKeyOpensTheConversation(_ chain: DialogueAcceptanceChain) throws {
        #expect(!chain.snapshot.isOpen)
        let speaker = try chain.pressUseKeyOnTheSpeaker()

        #expect(speaker == DialogueAcceptanceFixture.speakerKey)
        #expect(chain.activations.map(\.speaker) == [DialogueAcceptanceFixture.speakerKey])
        #expect(chain.snapshot.isOpen)
        #expect(chain.model.speakerKey == DialogueAcceptanceFixture.speakerKey)
        #expect(chain.model.state == .greeting)
        #expect(chain.model.subtitle == "Well met, traveller.")
        #expect(chain.snapshot.openMenus.contains("Dialogue Menu"))
        #expect(!chain.snapshot.worldSimPaused, "the dialogue menu must leave the world running")
        // A greeting is a delivered response, so it spends its say-once flag
        // the moment it is said rather than when the conversation ends.
        #expect(chain.saidCount(of: DialogueAcceptanceFixture.greetingInfo) == 1)
    }

    /// Step 2 — the list. Saying the greeting to its end hands the topic list
    /// back, and what is in it is what the conditions decided: the quest topic
    /// and the goodbye, but not the topic gated on a stage nobody has reached.
    /// The rejection is in the trace with its reason, which is what makes an
    /// absent topic explainable rather than mysterious.
    private static func theListIsConditionFiltered(_ chain: DialogueAcceptanceChain) throws {
        chain.finishTheLine()
        #expect(chain.model.state == .topicList)
        #expect(chain.topicTexts == ["I will help you.", "Farewell."])

        let rejected = try #require(chain.snapshot.rejections.first {
            $0.topic == FormID(DialogueAcceptanceFixture.stageTopic)
        })
        #expect(rejected.reasons.contains { $0.contains("conditions") })
        #expect(chain.snapshot.unresolvedConditionCount == 0, "every condition resolved")
    }

    /// Step 3 — the choice. Choosing the topic says its response, and its
    /// generated result script runs on the Papyrus VM and sets a stage on the
    /// M13 quest runtime. Nothing in the dialogue layer knows what a stage is:
    /// the stage is asserted through `QuestRuntime`, which never heard of a
    /// conversation.
    private static func choosingAResponseAdvancesTheQuest(_ chain: DialogueAcceptanceChain) throws {
        #expect(try !chain.questState().isStageDone(PapyrusQuestFixture.fragmentStage))

        try chain.chooseTopic(named: "I will help you.")
        #expect(chain.model.state == .response)
        #expect(chain.model.subtitle == "Then it is begun.")
        #expect(chain.saidCount(of: DialogueAcceptanceFixture.questInfo) == 1)

        chain.drainScripts()
        #expect(try chain.questState().isStageDone(PapyrusQuestFixture.fragmentStage))
        #expect(try chain.questState().isRunning)
    }

    /// Step 4 — the loop closing. Handing the list back re-selects it against
    /// the world the response just changed, so the stage-gated topic is now
    /// offered and the say-once line that set the stage is gone. The player
    /// sees the quest advance without opening the journal.
    private static func theQuestStageChangesWhatIsOffered(_ chain: DialogueAcceptanceChain) throws {
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
    private static func goodbyeEndsTheConversation(_ chain: DialogueAcceptanceChain) throws {
        try chain.chooseTopic(named: "Farewell.")
        #expect(chain.model.state == .response)
        #expect(chain.model.subtitle == "Safe roads.")

        chain.finishTheLine()
        #expect(!chain.snapshot.isOpen, "goodbye did not close the conversation")
        #expect(!chain.snapshot.openMenus.contains("Dialogue Menu"))
        #expect(chain.snapshot.subtitle == nil)
        #expect(chain.saidCount(of: DialogueAcceptanceFixture.goodbyeInfo) == 1)
    }

    /// Step 6 — persistence. Everything the conversation wrote is world state
    /// like any other, so it goes through the same encoder and decoder a save
    /// does, and comes back naming the same responses and the same stage.
    private static func theSaidStateSurvivesASaveAndLoad(_ chain: DialogueAcceptanceChain) throws {
        let restored = try chain.roundTripThroughASave()

        for info in [
            DialogueAcceptanceFixture.greetingInfo,
            DialogueAcceptanceFixture.questInfo,
            DialogueAcceptanceFixture.goodbyeInfo
        ] {
            let state = try #require(restored.component(
                DialogueRuntimeState.self, for: DialogueAcceptanceFixture.infoKey(info)
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
        _ chain: DialogueAcceptanceChain
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
