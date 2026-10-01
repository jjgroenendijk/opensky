// The dialogue shell over the fixture world: what it reads through
// `DialogueWorld`, the conversation steps, and the commands the speaker focus
// sends.

import OpenSkyConditions
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
import OpenSkyDialogueInterface
import OpenSkyDialogueTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState
import simd
import Testing

@MainActor
struct DialogueCoordinatorTests {
    private let speaker = DialogueRuntimeFixture.speakerKey

    private func coordinator(
        world: FakeDialogueWorld,
        store: WorldStateStore = WorldStateStore()
    ) throws -> DialogueCoordinator {
        let coordinator = DialogueCoordinator(store: store)
        coordinator.index = try DialogueRuntimeFixture.dialogueStore()
        coordinator.attach(world: world)
        return coordinator
    }

    private func world() throws -> FakeDialogueWorld {
        try FakeDialogueWorld(
            quests: QuestResolution(defaults: DialogueRuntimeFixture.questStore()),
            context: DialogueRuntimeFixture.context()
        )
    }

    // MARK: - Conversation

    @Test func withoutAnIndexNoConversationBegins() {
        let coordinator = DialogueCoordinator(store: WorldStateStore())
        #expect(coordinator.begin(with: speaker) == nil)
        #expect(coordinator.lastOutcome == "no dialogue index loaded")
    }

    @Test func withoutAQuestRuntimeNoConversationBegins() throws {
        let world = try world()
        world.quests = nil
        let coordinator = try coordinator(world: world)
        #expect(coordinator.begin(with: speaker) == nil)
    }

    @Test func beginKeepsTheSelectionForTheTrace() throws {
        let world = try world()
        let coordinator = try coordinator(world: world)
        #expect(coordinator.begin(with: speaker) != nil)
        #expect(coordinator.selection.offers.map(\.topic.rawValue) == [
            DialogueRuntimeFixture.urgentTopic,
            DialogueRuntimeFixture.ordinaryTopic
        ])
        #expect(coordinator.selection.rejected.contains {
            $0.topic.rawValue == DialogueRuntimeFixture.gatedTopic
        })
    }

    @Test func aRecordedGreetingIsSaid() throws {
        let world = try world()
        let store = WorldStateStore()
        let coordinator = try coordinator(world: world, store: store)
        let greeting = FormID(DialogueRuntimeFixture.greetingInfo)
        coordinator.recordGreeting(greeting, speaker: speaker)
        let runtime = try #require(coordinator.runtime)
        #expect(runtime.hasBeenSaid(greeting))
    }

    /// The response's topic links become the follow-up, and the list after the
    /// line shows them.
    @Test func choosingFollowsTheTopicLinks() throws {
        let world = try world()
        let coordinator = try coordinator(world: world)
        let id = FormID(DialogueRuntimeFixture.ordinaryInfo)
        let info = try #require(coordinator.choose(id, speaker: speaker))
        #expect(info.formID == id)
        #expect(coordinator.followUp?.next.offers.map(\.topic.rawValue)
            == [DialogueRuntimeFixture.urgentTopic])
        #expect(coordinator.lastOutcome?.hasPrefix("said ") == true)

        let end = coordinator.finishResponse(speaker: speaker)
        guard case let .topics(selection) = end else {
            Issue.record("expected topics, got \(end)")
            return
        }
        #expect(selection.offers.map(\.topic.rawValue) == [DialogueRuntimeFixture.urgentTopic])
        #expect(coordinator.followUp == nil)
    }

    /// A say-once line without links: the speaker's list is selected again,
    /// so the next response in the topic takes the spent one's place.
    @Test func aLineWithoutLinksSelectsTheTopicsAgain() throws {
        let world = try world()
        let coordinator = try coordinator(world: world)
        _ = coordinator.begin(with: speaker)
        let spent = FormID(DialogueRuntimeFixture.urgentFirstInfo)
        #expect(coordinator.choose(spent, speaker: speaker) != nil)

        let end = coordinator.finishResponse(speaker: speaker)
        guard case let .topics(selection) = end else {
            Issue.record("expected topics, got \(end)")
            return
        }
        let urgent = try #require(selection.offers.first {
            $0.topic.rawValue == DialogueRuntimeFixture.urgentTopic
        })
        #expect(urgent.info.rawValue == DialogueRuntimeFixture.urgentSecondInfo)
        #expect(coordinator.selection == selection)
    }

    @Test func anUnknownResponseIsRefusedWithItsFormID() throws {
        let world = try world()
        let coordinator = try coordinator(world: world)
        #expect(coordinator.choose(FormID(0xDEAD), speaker: speaker) == nil)
        #expect(coordinator.lastOutcome?.hasPrefix("no loaded plugin declares INFO") == true)
    }

    @Test func finishingWithoutARuntimeLeavesTheList() {
        let coordinator = DialogueCoordinator(store: WorldStateStore())
        #expect(coordinator.finishResponse(speaker: speaker) == .unchanged)
    }

    @Test func stringsLoadOnce() throws {
        let world = try world()
        let coordinator = try coordinator(world: world)
        _ = coordinator.strings
        _ = coordinator.strings
        #expect(world.stringLoads == 1)
    }

    // MARK: - Speaker focus

    @Test func focusHoldsOnceAndFacesEveryFrame() throws {
        let world = try world()
        let coordinator = try coordinator(world: world)
        let eye = SIMD3<Float>(1, 2, 3)
        coordinator.focus(on: speaker, playerEye: eye)
        coordinator.focus(on: speaker, playerEye: eye)
        #expect(coordinator.heldSpeaker == speaker)
        #expect(world.commands == [
            "suspend \(speaker)", "stop \(speaker)", "face \(speaker)", "face \(speaker)"
        ])
    }

    @Test func releaseHandsTheSpeakerBack() throws {
        let world = try world()
        let coordinator = try coordinator(world: world)
        coordinator.focus(on: speaker, playerEye: .zero)
        world.commands.removeAll()
        coordinator.releaseSpeakerFocus()
        coordinator.releaseSpeakerFocus()
        #expect(coordinator.heldSpeaker == nil)
        #expect(world.commands == ["release \(speaker)", "resume \(speaker)"])
    }
}

/// Answers `DialogueWorld` with the fixture's quests and conditions, and
/// records every actor command.
@MainActor
final class FakeDialogueWorld: DialogueWorld {
    var quests: QuestResolution?
    let context: ConditionContext
    private(set) var stringLoads = 0
    var commands: [String] = []

    init(quests: QuestResolution?, context: ConditionContext) {
        self.quests = quests
        self.context = context
    }

    func questStates() -> QuestResolution? {
        quests
    }

    func conditionContext() -> ConditionContext {
        context
    }

    var conditionRegistry: ConditionFunctionRegistry {
        .dialogueTests
    }

    var fragments: (any DialogueFragmentDispatching)? {
        nil
    }

    func loadStrings() -> LocalizedStrings? {
        stringLoads += 1
        return nil
    }

    func suspendPackage(for actor: ReferenceKey) {
        commands.append("suspend \(actor)")
    }

    func resumePackage(for actor: ReferenceKey) {
        commands.append("resume \(actor)")
    }

    func stopActor(_ actor: ReferenceKey) {
        commands.append("stop \(actor)")
    }

    func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>) {
        commands.append("face \(actor)")
    }

    func releaseFacing(of actor: ReferenceKey) {
        commands.append("release \(actor)")
    }
}
