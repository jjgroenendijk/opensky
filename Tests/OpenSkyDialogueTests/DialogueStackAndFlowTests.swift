// Response flags over a synthetic plugin: a Random stack picks one passing line, Say
// Once holds per speaker, and the coordinator plays Invisible Continue, walk-away,
// and Favors tab lines.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
@testable import OpenSkyDialogueInterface
import OpenSkyEngineTesting
import OpenSkyFeaturesTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct DialogueStackAndFlowTests {
    private static let topic: UInt32 = 0x100
    private static let linked: UInt32 = 0x110
    private static let walkAwayTopic: UInt32 = 0x120
    private static let favorTopic: UInt32 = 0x130
    private static let random: UInt16 = 0x02
    private static let sayOnce: UInt16 = 0x04
    private static let randomEnd: UInt16 = 0x20
    private static let invisibleContinue: UInt16 = 0x40
    private static let walkAway: UInt16 = 0x80
    private static let walkAwayHidden: UInt16 = 0x100

    private let speaker = DialogueRuntimeFixture.speakerKey

    private static func info(_ id: UInt32, flags: UInt16 = 0, extra: Data = Data()) -> Data {
        DialogueFixture.infoRecord(
            formID: id, fields: DialogueFixture.infoData(flags: flags) + extra
                + DialogueFixture.response()
        )
    }

    private static func topic(_ id: UInt32, extra: Data = Data(), infos: Data) -> Data {
        DialogueFixture.topicRecord(
            formID: id, fields: DialogueFixture.editorID("Topic\(id)") + extra
        ) + DialogueFixture.topicChildren(parent: id, infos: infos)
    }

    private func runtime(
        _ infos: Data, store: WorldStateStore = WorldStateStore(), pick: Int = 0
    ) throws -> DialogueRuntime {
        var runtime = try DialogueRuntime(
            store: store,
            dialogue: DialogueFixture.store(dialogueChildren: Self.topic(Self.topic, infos: infos)),
            context: DialogueRuntimeFixture.context(),
            registry: .dialogueTests
        )
        runtime.randomPick = { _ in pick }
        return runtime
    }

    private func offer(_ runtime: DialogueRuntime, speaker: ReferenceKey) -> DialogueTopicOffer? {
        runtime.topics(linked: [FormID(Self.topic)], speaker: speaker).offers.first
    }

    // MARK: - Random stacks

    /// Random lines stack up to the Random End line; the pick chooses among them,
    /// and the plain line after the stack is not reached.
    @Test(arguments: [0, 1, 2])
    func aRandomStackPicksOneLine(pick: Int) throws {
        let infos = Self.info(0x200, flags: Self.random) + Self.info(0x201, flags: Self.random)
            + Self.info(0x202, flags: Self.random | Self.randomEnd) + Self.info(0x203)
        let offer = try #require(try offer(runtime(infos, pick: pick), speaker: speaker))
        #expect(offer.info.rawValue == 0x200 + UInt32(pick))
        let rejections = offer.considered.map(\.rejection)
        #expect(rejections.filter { $0 == .lostRandomPick }.count == 2)
        #expect(rejections.last == .notReached)
    }

    /// A plain passing line closes the stack and joins it.
    @Test func aPlainLineClosesTheStack() throws {
        let infos = Self.info(0x200, flags: Self.random) + Self.info(0x201)
            + Self.info(0x202)
        let offer = try #require(try offer(runtime(infos, pick: 1), speaker: speaker))
        #expect(offer.info.rawValue == 0x201)
        #expect(offer.considered.map(\.rejection) == [.lostRandomPick, nil, .notReached])
    }

    // MARK: - Say Once

    /// A Say Once line is spent for the speaker who said it, not for another one.
    @Test func sayOnceHoldsPerSpeaker() throws {
        let store = WorldStateStore()
        let infos = Self.info(0x200, flags: Self.sayOnce) + Self.info(0x201)
        let runtime = try runtime(infos, store: store)
        try runtime.choose(FormID(0x200), speaker: speaker)
        let again = try #require(offer(runtime, speaker: speaker))
        #expect(again.info.rawValue == 0x201)
        #expect(again.considered.first?.rejection == .alreadySaid)
        let other = ConditionEvaluatorFixture.key(ConditionEvaluatorFixture.targetFormID)
        #expect(offer(runtime, speaker: other)?.info.rawValue == 0x200)
    }

    /// A count with no speaker, as an older save stores it, spends the line for all.
    @Test func aCountWithoutSpeakersCountsForEveryone() {
        let state = DialogueRuntimeState(saidCount: 1)
        #expect(state.hasBeenSaid(by: speaker))
        #expect(!DialogueRuntimeState().hasBeenSaid(by: speaker))
    }

    // MARK: - Coordinator flow

    private func coordinator(_ dialogue: Data) throws -> DialogueCoordinator {
        let world = try FakeDialogueWorld(
            quests: QuestResolution(defaults: DialogueRuntimeFixture.questStore()),
            context: DialogueRuntimeFixture.context()
        )
        let coordinator = DialogueCoordinator(store: WorldStateStore(), world: world)
        coordinator.index = try DialogueFixture.store(dialogueChildren: dialogue)
        return coordinator
    }

    /// Invisible Continue says the linked line next, with no choice list.
    @Test func anInvisibleContinuePlaysTheNextLine() throws {
        let coordinator = try coordinator(
            Self.topic(Self.topic, infos: Self.info(
                0x200, flags: Self.invisibleContinue, extra: DialogueFixture.word(
                    "TCLT",
                    Self.linked
                )
            )) + Self.topic(Self.linked, infos: Self.info(0x210))
        )
        _ = coordinator.choose(FormID(0x200), speaker: speaker)
        #expect(coordinator.finishResponse(speaker: speaker) == .continueWith(FormID(0x210)))
    }

    /// Backing out of a walk-away line's choice list says the walk-away topic, which
    /// the hidden flag keeps off the list.
    @Test(arguments: [true, false])
    func backingOutSaysTheWalkAwayLine(hidden: Bool) throws {
        let flags = Self.walkAway | (hidden ? Self.walkAwayHidden : 0)
        let coordinator = try coordinator(
            Self.topic(Self.topic, infos: Self.info(
                0x200, flags: flags,
                extra: DialogueFixture.word("TCLT", Self.linked)
                    + DialogueFixture.word("TCLT", Self.walkAwayTopic)
                    + DialogueFixture.word("TWAT", Self.walkAwayTopic)
            )) + Self.topic(Self.linked, infos: Self.info(0x210))
                + Self.topic(Self.walkAwayTopic, infos: Self.info(0x220))
        )
        _ = coordinator.choose(FormID(0x200), speaker: speaker)
        guard case let .topics(list) = coordinator.finishResponse(speaker: speaker) else {
            Issue.record("expected a choice list")
            return
        }
        let shown = list.offers.map(\.topic.rawValue)
        #expect(shown == (hidden ? [Self.linked] : [Self.linked, Self.walkAwayTopic]))
        #expect(coordinator.walkAway(speaker: speaker) == FormID(0x220))
        #expect(coordinator.runtime?.hasBeenSaid(FormID(0x220)) == true)
        #expect(coordinator.walkAway(speaker: speaker) == nil)
    }

    /// A Favors tab event says that event's line.
    @Test func aFavorEventSaysItsLine() throws {
        let coordinator = try coordinator(Self.topic(
            Self.favorTopic,
            extra: DialogueFixture.topicData(category: 4) + DialogueFixture.subtype("SHOW"),
            infos: Self.info(0x230)
        ))
        #expect(coordinator.favorLine("SHOW", speaker: speaker) == FormID(0x230))
        #expect(coordinator.favorLine("FEXT", speaker: speaker) == nil)
    }
}
