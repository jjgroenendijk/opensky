// Tags in dialogue text, read against the topic's quest. The hireling prompt
// carries `<Global=HirelingGold>`; the records below are synthetic.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@Suite("Dialogue text tags")
struct DialogueTextTagsTests {
    @Test func aGlobalTagShowsItsValue() throws {
        let quest = try QuestFixture.quest(formID: 0x0100, fields: QuestFixture.editorID("Hire"))
        let topic = try DialogueFixture.topic(DialogueFixture.word("QNAM", 0x0100))
        var naming = QuestAliasNaming { _, _ in nil }
        naming.global = { $0 == "HirelingGold" ? 500 : nil }
        let tags = DialogueTextTags(naming: naming) { $0 == quest.formID ? quest : nil }
        #expect(
            tags.fill("Consider yourself hired. (<Global=HirelingGold>)", topic: topic)
                == "Consider yourself hired. (500)"
        )
        #expect(tags.fill("No tags here.", topic: topic) == "No tags here.")
        #expect(DialogueTextTags.none.fill("(<Global=HirelingGold>)", topic: topic)
            == "(<Global=HirelingGold>)")
    }
}
