// Branch scoping of the opening topic list: a top-level branch offers only its
// starting topic, a blocking branch preempts the list, and an exclusive branch
// the speaker entered acts as blocking until a line from another branch.

import FormatsESMTesting
import Foundation
import GameDataTesting
@testable import OpenSkyConditions
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
@testable import OpenSkyDialogueInterface
import OpenSkyDialogueTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct DialogueBranchTests {
    static let quest = DialogueRuntimeFixture.runningQuest
    static let start: UInt32 = 0x1101
    static let follow: UInt32 = 0x1102
    static let branchless: UInt32 = 0x1103
    static let blockingStart: UInt32 = 0x1104
    static let exclusiveStart: UInt32 = 0x1105
    static let topLevel: UInt32 = 0x3001
    static let blocking: UInt32 = 0x3002
    static let exclusive: UInt32 = 0x3003

    static func info(_ topic: UInt32) -> UInt32 {
        topic + 0x1000
    }

    static func topic(_ id: UInt32, branch: UInt32?) -> Data {
        var fields = DialogueFixture.editorID("Topic\(id)") + DialogueFixture.topicData(category: 0)
            + DialogueFixture.subtype("CUST") + DialogueFixture.priority(50)
            + DialogueFixture.word("QNAM", quest)
        if let branch {
            fields += DialogueFixture.word("BNAM", branch)
        }
        return DialogueFixture.topicRecord(formID: id, fields: fields)
            + DialogueFixture.topicChildren(
                parent: id,
                infos: DialogueFixture.infoRecord(
                    formID: info(id),
                    fields: DialogueFixture.infoData()
                        + DialogueFixture.isSpeaker(DialogueRuntimeFixture.speakerBase)
                )
            )
    }

    func runtime(
        withBlocking: Bool = false,
        store: WorldStateStore = WorldStateStore()
    ) throws -> DialogueRuntime {
        let topics = Self.topic(Self.start, branch: Self.topLevel)
            + Self.topic(Self.follow, branch: Self.topLevel)
            + Self.topic(Self.branchless, branch: nil)
            + Self.topic(Self.blockingStart, branch: Self.blocking)
            + Self.topic(Self.exclusiveStart, branch: Self.exclusive)
        let branches = DialogueFixture.branchRecord(
            formID: Self.topLevel, quest: Self.quest, flags: 1, startingTopic: Self.start
        )
            + DialogueFixture.branchRecord(
                formID: Self.blocking, quest: Self.quest, flags: withBlocking ? 2 : 0,
                startingTopic: Self.blockingStart
            )
            + DialogueFixture.branchRecord(
                formID: Self.exclusive, quest: Self.quest, flags: 4,
                startingTopic: Self.exclusiveStart
            )
        let quests = try DialogueRuntimeFixture.questStore()
        return try DialogueRuntime(
            store: store,
            dialogue: DialogueFixture.store(dialogueChildren: topics, branchRecords: branches),
            questStates: QuestResolution(defaults: quests),
            context: DialogueRuntimeFixture.context(),
            registry: .dialogueTests
        )
    }

    private var speaker: ReferenceKey {
        DialogueRuntimeFixture.speakerKey
    }

    /// The starting topic of a top-level branch and a branchless topic open the
    /// list. A topic deeper in the branch, and a normal branch's start, do not.
    @Test func topLevelStartsAndBranchlessTopicsAreOffered() throws {
        let selection = try runtime().topics(for: speaker)
        #expect(Set(selection.offers.map(\.topic.rawValue)) == [Self.start, Self.branchless])
        let scoped = selection.rejected.filter { $0.considered.first?.rejection == .notBranchEntry }
        #expect(Set(scoped.map(\.topic.rawValue)) == [
            Self.follow,
            Self.blockingStart,
            Self.exclusiveStart
        ])
    }

    /// A topic inside a branch is still reachable through a link: choosing works.
    @Test func aNonEntryTopicIsReachableByChoosingIt() throws {
        let runtime = try runtime()
        let choice = try runtime.choose(FormID(Self.info(Self.follow)), speaker: speaker)
        #expect(runtime.saidState(of: FormID(Self.info(Self.follow))).saidCount == 1)
        #expect(!choice.endsConversation)
    }

    /// A running blocking branch whose start answers is the only topic and the greeting.
    @Test func aBlockingBranchPreemptsTheList() throws {
        let runtime = try runtime(withBlocking: true)
        let selection = runtime.topics(for: speaker)
        #expect(selection.offers.map(\.topic.rawValue) == [Self.blockingStart])
        #expect(selection.rejected.contains {
            $0.topic.rawValue == Self.start
                && $0.considered.first?.rejection == .blockedByBranch(FormID(Self.blocking))
        })
        #expect(runtime.greeting(for: speaker)?.topic.rawValue == Self.blockingStart)
    }

    /// A line from an exclusive branch holds the speaker there, across a save of the
    /// store, until a line from a branch that is not exclusive.
    @Test func anExclusiveBranchHoldsUntilAnotherBranchSpeaks() throws {
        let store = WorldStateStore()
        let runtime = try runtime(store: store)
        try runtime.choose(FormID(Self.info(Self.exclusiveStart)), speaker: speaker)
        #expect(runtime.exclusiveBranch(of: speaker) == FormID(Self.exclusive))
        #expect(runtime.topics(for: speaker).offers.map(\.topic.rawValue) == [Self.exclusiveStart])

        let restored = WorldStateStore()
        restored.restore(from: store.snapshot())
        #expect(try self.runtime(store: restored)
            .exclusiveBranch(of: speaker) == FormID(Self.exclusive))

        try runtime.choose(FormID(Self.info(Self.start)), speaker: speaker)
        #expect(runtime.exclusiveBranch(of: speaker) == nil)
        #expect(runtime.topics(for: speaker).offers.count == 2)
    }

    /// A branchless line leaves the exclusive branch in place.
    @Test func aBranchlessLineKeepsTheExclusiveBranch() throws {
        let runtime = try runtime()
        try runtime.choose(FormID(Self.info(Self.exclusiveStart)), speaker: speaker)
        try runtime.choose(FormID(Self.info(Self.branchless)), speaker: speaker)
        #expect(runtime.exclusiveBranch(of: speaker) == FormID(Self.exclusive))
    }
}
