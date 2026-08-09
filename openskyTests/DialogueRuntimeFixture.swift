// The synthetic world `DialogueRuntimeTests` and `DialogueSaveTests` select
// against: two quests, five topics and the responses under them, every byte
// built in code through `DialogueFixture` and `QuestFixture`.
//
// One world rather than one per test, because the interesting properties are
// about how topics compete with each other — priority order, a quest gate, a
// say-once line dropping out — and each of those needs the others present to
// mean anything.
//
// The shape mirrors what the vanilla probe found rather than a convenient
// invention: every topic names an owning quest, the responses gate on
// `GetIsID` for the speaker, and the follow-up flow runs through TCLT links
// rather than through a previous-info chain, which `Skyrim.esm` uses zero times.

import Foundation
@testable import opensky

enum DialogueRuntimeFixture {
    /// Start-game-enabled, so it runs off its DNAM flag with nothing started.
    static let runningQuest: UInt32 = 0x0000_0100
    /// Not start-game-enabled, so every topic it owns is filtered out.
    static let dormantQuest: UInt32 = 0x0000_0101

    static let greetingTopic: UInt32 = 0x0000_1000
    /// Priority 90, so it leads the offered list.
    static let urgentTopic: UInt32 = 0x0000_1001
    /// Priority 50, and the one whose responses compete in file order.
    static let ordinaryTopic: UInt32 = 0x0000_1002
    /// Owned by the dormant quest.
    static let gatedTopic: UInt32 = 0x0000_1003
    /// A scene topic, which is never a player choice whatever its conditions
    /// say.
    static let sceneTopic: UInt32 = 0x0000_1004

    static let greetingInfo: UInt32 = 0x0000_2000
    /// Say-once, and first in file order under the urgent topic.
    static let urgentFirstInfo: UInt32 = 0x0000_2001
    /// The fallback the urgent topic offers once the say-once line is spent.
    static let urgentSecondInfo: UInt32 = 0x0000_2002
    /// Conditions name a different speaker, so it never wins.
    static let ordinaryWrongSpeakerInfo: UInt32 = 0x0000_2003
    /// The winner under the ordinary topic; links to the urgent topic and
    /// carries a result script.
    static let ordinaryInfo: UInt32 = 0x0000_2004
    /// After the winner in file order, so it is never reached.
    static let ordinaryUnreachedInfo: UInt32 = 0x0000_2005
    static let gatedInfo: UInt32 = 0x0000_2006
    static let sceneInfo: UInt32 = 0x0000_2007

    /// Generated result script of `ordinaryInfo`, named the way the Creation
    /// Kit names one for a record with no editor ID.
    static let resultScript = "TIF__00002004"
    static let beginFunction = "Fragment_0"
    static let endFunction = "Fragment_1"

    /// Base NPC_ the speaker is a placement of, and the one every winning
    /// response's `GetIsID` names.
    static let speakerBase = ConditionEvaluatorFixture.subjectBase
    static let otherBase = ConditionEvaluatorFixture.targetBase

    static var speakerKey: ReferenceKey {
        ConditionEvaluatorFixture.key(ConditionEvaluatorFixture.subjectFormID)
    }

    static func infoKey(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: DialogueFixture.pluginName, objectID: objectID)
    }

    // MARK: - Stores

    static func dialogueStore() throws -> DialogueStore {
        try DialogueFixture.store(dialogueChildren: topics())
    }

    static func questStore() throws -> QuestStore {
        try QuestFixture.store(
            QuestFixture.record(
                formID: runningQuest,
                fields: QuestFixture.editorID("OpenSkyDialogueRunning")
                    + QuestFixture.general(flags: 1)
            )
                + QuestFixture.record(
                    formID: dormantQuest,
                    fields: QuestFixture.editorID("OpenSkyDialogueDormant")
                        + QuestFixture.general(flags: 0)
                )
        )
    }

    /// A runtime over a fresh store, with the speaker placed and the two
    /// quests reading from plugin data.
    @MainActor
    static func runtime(
        store: WorldStateStore = WorldStateStore(),
        fragments: (any DialogueFragmentDispatching)? = nil
    ) throws -> DialogueRuntime {
        let quests = try questStore()
        return try DialogueRuntime(
            store: store,
            dialogue: dialogueStore(),
            quests: quests,
            questStates: QuestResolution(defaults: quests),
            context: context(),
            fragments: fragments
        )
    }

    static func context() throws -> ConditionContext {
        try ConditionContext(
            quests: .empty,
            references: ConditionEvaluatorFixture.references([
                (formID: ConditionEvaluatorFixture.subjectFormID, base: speakerBase),
                (formID: ConditionEvaluatorFixture.targetFormID, base: otherBase)
            ]),
            subject: speakerKey,
            target: .player
        )
    }

    // MARK: - Records

    private static func topics() -> Data {
        greeting() + urgent() + ordinary() + gated() + scene()
    }

    private static func greeting() -> Data {
        DialogueFixture.topicRecord(
            formID: greetingTopic,
            fields: DialogueFixture.editorID("OpenSkyGreeting")
                // Category 7, miscellaneous: a greeting is not a topic the
                // player picks, so it is deliberately not category 0.
                + DialogueFixture.topicData(category: 7)
                + DialogueFixture.subtype("HELO")
                + DialogueFixture.priority(50)
                + DialogueFixture.word("QNAM", runningQuest)
        )
            + DialogueFixture.topicChildren(
                parent: greetingTopic,
                infos: DialogueFixture.infoRecord(
                    formID: greetingInfo,
                    fields: DialogueFixture.infoData()
                        + DialogueFixture.isSpeaker(speakerBase)
                )
            )
    }

    private static func urgent() -> Data {
        DialogueFixture.topicRecord(
            formID: urgentTopic,
            fields: DialogueFixture.editorID("OpenSkyUrgent")
                + DialogueFixture.topicData(category: 0)
                + DialogueFixture.subtype("CUST")
                + DialogueFixture.priority(90)
                + DialogueFixture.word("QNAM", runningQuest)
        )
            + DialogueFixture.topicChildren(
                parent: urgentTopic,
                infos: DialogueFixture.infoRecord(
                    formID: urgentFirstInfo,
                    // Flag bit 2 is say once.
                    fields: DialogueFixture.infoData(flags: 1 << 2)
                        + DialogueFixture.isSpeaker(speakerBase)
                )
                    + DialogueFixture.infoRecord(
                        formID: urgentSecondInfo,
                        fields: DialogueFixture.infoData()
                            + DialogueFixture.isSpeaker(speakerBase)
                    )
            )
    }

    private static func ordinary() -> Data {
        DialogueFixture.topicRecord(
            formID: ordinaryTopic,
            fields: DialogueFixture.editorID("OpenSkyOrdinary")
                + DialogueFixture.topicData(category: 0)
                + DialogueFixture.subtype("CUST")
                + DialogueFixture.priority(50)
                + DialogueFixture.word("QNAM", runningQuest)
        )
            + DialogueFixture.topicChildren(
                parent: ordinaryTopic,
                infos: DialogueFixture.infoRecord(
                    formID: ordinaryWrongSpeakerInfo,
                    fields: DialogueFixture.infoData()
                        + DialogueFixture.isSpeaker(otherBase)
                )
                    + DialogueFixture.infoRecord(
                        formID: ordinaryInfo,
                        fields: DialogueFixture.infoData()
                            + DialogueFixture.vmad(tail: DialogueFixture.infoFragmentTail(
                                fileName: resultScript,
                                begin: beginFunction,
                                end: endFunction
                            ))
                            + DialogueFixture.isSpeaker(speakerBase)
                            + DialogueFixture.word("TCLT", urgentTopic)
                    )
                    + DialogueFixture.infoRecord(
                        formID: ordinaryUnreachedInfo,
                        fields: DialogueFixture.infoData()
                            + DialogueFixture.isSpeaker(speakerBase)
                    )
            )
    }

    private static func gated() -> Data {
        DialogueFixture.topicRecord(
            formID: gatedTopic,
            fields: DialogueFixture.editorID("OpenSkyGated")
                + DialogueFixture.topicData(category: 0)
                + DialogueFixture.subtype("CUST")
                + DialogueFixture.priority(99)
                + DialogueFixture.word("QNAM", dormantQuest)
        )
            + DialogueFixture.topicChildren(
                parent: gatedTopic,
                infos: DialogueFixture.infoRecord(
                    formID: gatedInfo,
                    fields: DialogueFixture.infoData()
                        + DialogueFixture.isSpeaker(speakerBase)
                )
            )
    }

    private static func scene() -> Data {
        DialogueFixture.topicRecord(
            formID: sceneTopic,
            fields: DialogueFixture.editorID("OpenSkyScene")
                + DialogueFixture.topicData(category: 2)
                + DialogueFixture.subtype("SCEN")
                + DialogueFixture.priority(99)
                + DialogueFixture.word("QNAM", runningQuest)
        )
            + DialogueFixture.topicChildren(
                parent: sceneTopic,
                infos: DialogueFixture.infoRecord(
                    formID: sceneInfo,
                    fields: DialogueFixture.infoData()
                        + DialogueFixture.isSpeaker(speakerBase)
                )
            )
    }
}
