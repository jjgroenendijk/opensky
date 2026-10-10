// Shared responses (`INFO` `DNAM`) and reset times over a synthetic plugin: a
// shared line says its target's responses and voice files, and a line with a
// reset time waits that many game hours before the same speaker says it again.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
@testable import OpenSkyDialogueInterface
import OpenSkyEngineTesting
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct DialogueSharedAndResetTests {
    private static let topic: UInt32 = 0x100
    private static let sharedTopic: UInt32 = 0x110
    private static let resetInfo: UInt32 = 0x200
    private static let fallbackInfo: UInt32 = 0x201
    private static let sharedTarget: UInt32 = 0x300
    /// ENAM's 0...65535 maps to 0...24 hours, so this is 12 hours.
    private static let twelveHours: UInt16 = 32768

    // MARK: - Reset times

    private func resetStore() throws -> DialogueStore {
        try DialogueFixture.store(dialogueChildren: DialogueFixture.topicRecord(
            formID: Self.topic, fields: DialogueFixture.editorID("ResetTopic")
        ) + DialogueFixture.topicChildren(
            parent: Self.topic,
            infos: DialogueFixture.infoRecord(
                formID: Self.resetInfo,
                fields: DialogueFixture.infoData(reset: Self.twelveHours)
                    + DialogueFixture.response()
            ) + DialogueFixture.infoRecord(
                formID: Self.fallbackInfo,
                fields: DialogueFixture.infoData() + DialogueFixture.response()
            )
        ))
    }

    private func runtime(
        store: WorldStateStore, dialogue: DialogueStore, hour: Float?
    ) throws -> DialogueRuntime {
        var context = try DialogueRuntimeFixture.context()
        if let hour {
            // The clock answers only through the time global's record, as in Skyrim.esm.
            context.globals = try GlobalResolution(
                defaults: GlobalFixture.store(GlobalFixture.record(
                    formID: 0x900, editorID: "GameDaysPassed", type: .float, value: 0
                )),
                clock: GameClock(hour: hour)
            )
        }
        return DialogueRuntime(
            store: store, dialogue: dialogue, context: context, registry: .dialogueTests
        )
    }

    private func winner(
        _ runtime: DialogueRuntime,
        speaker: ReferenceKey = DialogueRuntimeFixture.speakerKey
    ) -> DialogueTopicOffer? {
        runtime.topics(linked: [FormID(Self.topic)], speaker: speaker).offers.first
    }

    @Test func aSaidLineWaitsForItsResetTime() throws {
        let store = WorldStateStore()
        let dialogue = try resetStore()
        let speaker = DialogueRuntimeFixture.speakerKey
        try runtime(store: store, dialogue: dialogue, hour: 8)
            .choose(FormID(Self.resetInfo), speaker: speaker)
        let said = try runtime(store: store, dialogue: dialogue, hour: 8)
            .saidState(of: FormID(Self.resetInfo))
        #expect(said.saidDays == [speaker: Double(GameClock(hour: 8).daysPassed)])

        let soon = try #require(try winner(runtime(store: store, dialogue: dialogue, hour: 14)))
        #expect(soon.info.rawValue == Self.fallbackInfo)
        #expect(soon.considered.first?.rejection == .waitingForReset)

        let later = try #require(try winner(runtime(store: store, dialogue: dialogue, hour: 21)))
        #expect(later.info.rawValue == Self.resetInfo)
    }

    /// The wait belongs to the speaker who said the line; another may say it at once.
    @Test func anotherSpeakerDoesNotWait() throws {
        let store = WorldStateStore()
        let dialogue = try resetStore()
        try runtime(store: store, dialogue: dialogue, hour: 8)
            .choose(FormID(Self.resetInfo), speaker: DialogueRuntimeFixture.speakerKey)
        let other = ConditionEvaluatorFixture.key(ConditionEvaluatorFixture.targetFormID)
        let offer = try winner(runtime(store: store, dialogue: dialogue, hour: 9), speaker: other)
        #expect(offer?.info.rawValue == Self.resetInfo)
    }

    /// With no clock nothing can be measured, so the line is not held back.
    @Test func aLineIsNotHeldBackWithoutAClock() throws {
        let store = WorldStateStore()
        let dialogue = try resetStore()
        let unclocked = try runtime(store: store, dialogue: dialogue, hour: nil)
        try unclocked.choose(FormID(Self.resetInfo), speaker: DialogueRuntimeFixture.speakerKey)
        #expect(unclocked.saidState(of: FormID(Self.resetInfo)).saidDays.isEmpty)
        #expect(winner(unclocked)?.info.rawValue == Self.resetInfo)
    }

    @Test func aLineWithNoResetTimeRepeatsAtOnce() {
        let speaker = DialogueRuntimeFixture.speakerKey
        let state = DialogueRuntimeState().said(by: speaker, onDay: 3)
        #expect(state.hasReset(resetHours: 0, speaker: speaker, onDay: 3))
        #expect(!state.hasReset(resetHours: 1, speaker: speaker, onDay: 3))
        #expect(state.hasReset(resetHours: 24, speaker: speaker, onDay: 4))
    }

    // MARK: - Shared responses

    private func sharedStore(targetLink: UInt32 = 0) throws -> DialogueStore {
        let target = DialogueFixture.infoRecord(
            formID: Self.sharedTarget,
            fields: DialogueFixture.infoData()
                + (targetLink == 0 ? Data() : DialogueFixture.word("DNAM", targetLink))
                + DialogueFixture.response(number: 1)
                + DialogueFixture.response(number: 2)
        )
        return try DialogueFixture.store(dialogueChildren: DialogueFixture.topicRecord(
            formID: Self.topic, fields: DialogueFixture.editorID("AskTopic")
        ) + DialogueFixture.topicChildren(
            parent: Self.topic,
            infos: DialogueFixture.infoRecord(
                formID: Self.resetInfo,
                fields: DialogueFixture.infoData()
                    + DialogueFixture.word("DNAM", Self.sharedTarget)
            )
        ) + DialogueFixture.topicRecord(
            formID: Self.sharedTopic, fields: DialogueFixture.editorID("SharedInfos")
        ) + DialogueFixture.topicChildren(parent: Self.sharedTopic, infos: target))
    }

    @Test func aSharedLineSaysItsTargetsResponses() throws {
        let dialogue = try sharedStore()
        let source = try #require(dialogue.responseSource(ofInfo: FormID(Self.resetInfo)))
        #expect(source.formID.rawValue == Self.sharedTarget)
        #expect(source.responses.count == 2)
        #expect(dialogue.responseSource(ofInfo: FormID(Self.sharedTarget))?.formID
            .rawValue == Self.sharedTarget)
    }

    @Test func aSharedLinePlaysItsTargetsVoiceFiles() throws {
        let dialogue = try sharedStore()
        let locator = VoiceLineLocator(dialogue: dialogue, quests: nil)
        let info = try #require(dialogue.info(FormID(Self.resetInfo)))
        let names = locator.lines(info: info, voiceType: "MaleEvenToned")
            .map { $0.path.split(separator: "\\").last.map(String.init) ?? "" }
        #expect(names == ["_sharedinfos_00000300_1.fuz", "_sharedinfos_00000300_2.fuz"])
    }

    /// Two INFOs that share each other stop at the second, not in a loop.
    @Test func aLoopOfSharedLinksStops() throws {
        let dialogue = try sharedStore(targetLink: Self.resetInfo)
        let source = dialogue.responseSource(ofInfo: FormID(Self.resetInfo))
        #expect(source?.formID.rawValue == Self.sharedTarget)
    }
}
