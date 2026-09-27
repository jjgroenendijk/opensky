// DIAL decoder tests over synthetic bytes. Layout: UESP DIAL and xEdit
// dev-4.1.6 `wbRecord(DIAL, ...)`.

import Foundation
@testable import opensky
import Testing

struct DialogueTopicRecordTests {
    @Test func decodesTopicLinksCategoryAndSubtype() throws {
        let fields = DialogueFixture.editorID("MQ101Greeting")
            + DialogueFixture.inlineText("FULL", "Any news?")
            + DialogueFixture.priority(75.5)
            + DialogueFixture.word("BNAM", 0x400)
            + DialogueFixture.word("QNAM", 0x500)
            + DialogueFixture.topicData(repeatsAll: true, category: 3, legacySubtype: 79)
            + DialogueFixture.subtype("HELO")
            + DialogueFixture.word("TIFC", 2)
        let topic = try DialogueFixture.topic(fields)

        #expect(topic.editorID == "MQ101Greeting")
        #expect(topic.name == .inline("Any news?"))
        #expect(topic.priority == 75.5)
        #expect(topic.owningBranch == FormID(0x400))
        #expect(topic.owningQuest == FormID(0x500))
        #expect(topic.doAllBeforeRepeating)
        #expect(topic.category == .combat)
        #expect(topic.legacySubtype == 79)
        #expect(topic.subtype == "HELO")
        #expect(topic.declaredInfoCount == 2)
        #expect(topic.skipped.isEmpty)
    }

    @Test func decodesCompressedTopic() throws {
        let bytes = DialogueFixture.topicRecord(
            fields: DialogueFixture.editorID("CompressedTopic")
                + DialogueFixture.priority(50)
                + DialogueFixture.topicData(),
            compressed: true
        )
        let topic = try DialogueTopic(record: DialogueFixture.parse(bytes))
        #expect(topic.editorID == "CompressedTopic")
        #expect(topic.priority == 50)
    }

    @Test func talliesMalformedAndUnknownFieldsWithoutThrowing() throws {
        let topic = try DialogueFixture.topic(
            ESMFixture.field("PNAM", Data([1]))
                + ESMFixture.field("ZZZZ", Data())
                + DialogueFixture.editorID("StillUsable")
        )
        #expect(topic.editorID == "StillUsable")
        #expect(topic.skipped.total == 2)
        #expect(topic.skipped.counts[.malformedField("PNAM")] == 1)
        #expect(topic.skipped.counts[.unknownField("ZZZZ")] == 1)
    }
}
