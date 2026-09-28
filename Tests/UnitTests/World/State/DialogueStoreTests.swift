// DialogueStore's group descent and order-preserving indexes over one
// synthetic plugin. No game data is embedded.

import Foundation
@testable import opensky
import Testing

struct DialogueStoreTests {
    @Test func descendsTopicGroupsAndPreservesInfoOrder() throws {
        let topic = DialogueFixture.topicRecord(
            formID: 0x100,
            fields: DialogueFixture.editorID("Greeting")
                + DialogueFixture.priority(50)
                + DialogueFixture.topicData()
        )
        let first = DialogueFixture.infoRecord(
            formID: 0x201,
            fields: DialogueFixture.infoData() + DialogueFixture.response(number: 1)
        )
        let second = DialogueFixture.infoRecord(
            formID: 0x202,
            fields: DialogueFixture.infoData() + DialogueFixture.response(number: 2),
            compressed: true
        )
        let voice = DialogueFixture.voiceRecord(
            formID: 0x300,
            fields: DialogueFixture.editorID("MaleNord")
                + ESMFixture.field("DNAM", Data([1]))
        )
        let store = try DialogueFixture.store(
            dialogueChildren: topic
                + DialogueFixture.topicChildren(parent: 0x100, infos: first + second),
            voiceRecords: voice
        )

        #expect(store.topicCount == 1)
        #expect(store.infoCount == 2)
        #expect(store.voiceTypeCount == 1)
        #expect(store.topic(editorID: "greeting")?.formID == FormID(0x100))
        #expect(store.infos(for: FormID(0x100)).map(\.formID)
            == [FormID(0x201), FormID(0x202)])
        #expect(store.info(FormID(0x202))?.responses.first?.number == 2)
        #expect(store.voiceType(editorID: "malenord")?.formID == FormID(0x300))
        #expect(store.skippedRecordCount == 0)
    }

    @Test func countsStructurallyUnreadableRecords() throws {
        let malformed = DialogueFixture.topicRecord(formID: 0x100, fields: Data([0]))
        let store = try DialogueFixture.store(dialogueChildren: malformed)
        #expect(store.topicCount == 0)
        #expect(store.skippedRecordCount == 1)
    }

    @Test func emptyPluginYieldsEmptyStore() throws {
        let store = try DialogueFixture.store()
        #expect(store.isEmpty)
        #expect(DialogueStore.empty.isEmpty)
    }
}
