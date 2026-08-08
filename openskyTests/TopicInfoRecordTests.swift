// INFO response-run, flags, condition and localization tests over synthetic
// bytes. Layout: UESP INFO and xEdit dev-4.1.6 `wbRecord(INFO, ...)`.

import Foundation
@testable import opensky
import Testing

struct TopicInfoRecordTests {
    @Test func decodesResponsesFlagsLinksAndConditions() throws {
        var fields = DialogueFixture.editorID("MQ101Greeting01")
        fields += DialogueFixture.infoData(flags: 0x6005, reset: UInt16.max / 2)
        fields += DialogueFixture.word("TPIC", 0x101)
        fields += DialogueFixture.word("PNAM", 0x201)
        fields += ESMFixture.field("CNAM", Data([2]))
        fields += DialogueFixture.word("TCLT", 0x301)
        fields += DialogueFixture.word("TCLT", 0x302)
        fields += DialogueFixture.word("DNAM", 0x202)
        fields += DialogueFixture.response(
            emotion: 5,
            emotionValue: 80,
            number: 7,
            sound: 0x401,
            usesEmotionAnimation: true
        )
        fields += DialogueFixture.inlineText("NAM1", "First response")
        fields += DialogueFixture.inlineText("NAM2", "Actor note")
        fields += DialogueFixture.word("SNAM", 0x501)
        fields += DialogueFixture.response(emotion: 1, number: 8)
        fields += DialogueFixture.inlineText("NAM1", "Second response")
        fields += DialogueFixture.condition(functionIndex: 77)
        fields += DialogueFixture.inlineText("RNAM", "Choose this")
        fields += DialogueFixture.word("ANAM", 0x601)
        fields += DialogueFixture.word("TWAT", 0x701)
        fields += DialogueFixture.word("ONAM", 0x801)
        let info = try DialogueFixture.info(fields)

        #expect(info.editorID == "MQ101Greeting01")
        #expect(info.flags.contains(TopicInfo.Flags.goodbye))
        #expect(info.flags.contains(TopicInfo.Flags.sayOnce))
        #expect(info.flags.contains(TopicInfo.Flags.hasAudioOutputOverride))
        #expect(info.flags.contains(TopicInfo.Flags.spendsFavorPoints))
        #expect(abs(info.resetHours - 12) < 0.01)
        #expect(info.previousTopic == FormID(0x101))
        #expect(info.previousInfo == FormID(0x201))
        #expect(info.favorLevel == .medium)
        #expect(info.topicLinks == [FormID(0x301), FormID(0x302)])
        #expect(info.sharedInfo == FormID(0x202))
        #expect(info.responses.count == 2)
        let first: TopicInfo.Response = try #require(info.responses.first)
        #expect(first.emotion == TopicInfo.Response.Emotion.happy)
        #expect(first.emotionValue == 80)
        #expect(first.number == 7)
        #expect(first.sound == FormID(0x401))
        #expect(first.usesEmotionAnimation)
        #expect(first.text == LString.inline("First response"))
        #expect(first.scriptNotes == "Actor note")
        #expect(first.speakerIdle == FormID(0x501))
        #expect(info.conditions.conditions.count == 1)
        #expect(info.conditions.conditions.first?.functionIndex == 77)
        #expect(info.prompt == LString.inline("Choose this"))
        #expect(info.speaker == FormID(0x601))
        #expect(info.walkAwayTopic == FormID(0x701))
        #expect(info.audioOutputOverride == FormID(0x801))
        #expect(info.skipped.isEmpty)
    }

    @Test func responseTextResolvesThroughILStrings() throws {
        let dataURL = FileManager.default.temporaryDirectory.appending(
            path: "TopicInfoStrings-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: dataURL.appending(path: "Strings", directoryHint: .isDirectory),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: dataURL) }
        try StringTableFixture.table(
            kind: .dlstrings,
            entries: [(id: 0x42, text: "Wrong DL entry")]
        ).write(to: dataURL.appending(path: "Strings/Test_English.dlstrings"))
        try StringTableFixture.table(
            kind: .ilstrings,
            entries: [(id: 0x42, text: "The IL dialogue line")]
        ).write(to: dataURL.appending(path: "Strings/Test_English.ilstrings"))
        let info = try DialogueFixture.info(
            DialogueFixture.response()
                + DialogueFixture.localizedText("NAM1", id: 0x42),
            localized: true
        )
        let strings = LocalizedStrings(
            vfs: VirtualFileSystem(dataURL: dataURL, archiveURLs: []),
            pluginName: "Test.esm"
        )

        #expect(info.responses.first?.resolvedText(using: strings) == "The IL dialogue line")
    }

    @Test func talliesMalformedAndOrphanResponseFields() throws {
        let info = try DialogueFixture.info(
            DialogueFixture.inlineText("NAM1", "orphan")
                + ESMFixture.field("TRDT", Data(count: 4))
                + DialogueFixture.editorID("StillUsable")
        )
        #expect(info.editorID == "StillUsable")
        #expect(info.responses.isEmpty)
        #expect(info.skipped.counts[.orphanResponseField("NAM1")] == 1)
        #expect(info.skipped.counts[.malformedField("TRDT")] == 1)
    }
}
