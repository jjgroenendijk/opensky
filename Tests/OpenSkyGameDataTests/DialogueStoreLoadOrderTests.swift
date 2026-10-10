// DialogueStore over a load order: a DLC that loads later than its own master index
// says, and adds an INFO to a topic of its master. No game data is embedded.

import Foundation
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct DialogueStoreLoadOrderTests {
    /// The DLC lists one master, so it writes its own forms as 0x01xxxxxx. It loads
    /// third, so the load order numbers them 0x02xxxxxx.
    private static func store() throws -> DialogueStore {
        let base = DialogueFixture.plugin(
            dialogueChildren: topic(0x100, "Greeting")
                + DialogueFixture.topicChildren(parent: 0x100, infos: info(0x201))
        )
        let dlc = ESMFixture.tes4(masters: ["Base.esm"]) + ESMFixture.topGroup(
            "DIAL",
            contents: topic(0x100, "Greeting")
                + DialogueFixture.topicChildren(parent: 0x100, infos: info(0x0100_0202))
                + topic(0x0100_0300, "DLCTopic")
                + DialogueFixture.topicChildren(parent: 0x0100_0300, infos: info(0x0100_0301))
        )
        return try DialogueStore(plugins: [
            (name: "Base.esm", file: ESMFile(data: base)),
            (name: "Mid.esm", file: ESMFile(data: ESMFixture.tes4())),
            (name: "DLC.esm", file: ESMFile(data: dlc))
        ])
    }

    private static func topic(_ formID: UInt32, _ editorID: String) -> Data {
        DialogueFixture.topicRecord(
            formID: formID,
            fields: DialogueFixture.editorID(editorID) + DialogueFixture.topicData()
        )
    }

    private static func info(_ formID: UInt32) -> Data {
        DialogueFixture.infoRecord(
            formID: formID,
            fields: DialogueFixture.infoData() + DialogueFixture.response(number: 1)
        )
    }

    @Test func aDLCInfoJoinsItsMastersTopicInLoadOrderSpace() throws {
        let store = try Self.store()
        #expect(store.infos(for: FormID(0x100)).map(\.formID) == [
            FormID(0x201),
            FormID(0x0200_0202)
        ])
        #expect(store.key(forInfo: FormID(0x0200_0202)) == .plugin(
            name: "dlc.esm",
            objectID: 0x202
        ))
    }

    @Test func aDLCTopicIsRenumberedToItsLoadPosition() throws {
        let store = try Self.store()
        #expect(store.topic(editorID: "DLCTopic")?.formID == FormID(0x0200_0300))
        #expect(store.infos(for: FormID(0x0200_0300)).map(\.formID) == [FormID(0x0200_0301)])
        #expect(store.topic(FormID(0x0100_0300)) == nil)
    }

    @Test func anInfoTranslatesTheFormIDsItsOwnPluginWrote() throws {
        let store = try Self.store()
        let dlc = try #require(store.translation(ofInfo: FormID(0x0200_0301)))
        #expect(dlc(FormID(0x0100_0300)) == FormID(0x0200_0300))
        #expect(dlc(FormID(0x0000_0100)) == FormID(0x100))
        #expect(store.translation(ofInfo: FormID(0x201))?.source.pluginName == "Base.esm")
    }
}
