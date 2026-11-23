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

    /// The engine fills `<CrimeGold>` and `<BribeCost>` from the speaker, with or without a
    /// quest, and leaves a tag it has no value for as written.
    @Test func theSpeakerTagsShowTheirGold() {
        let tags = DialogueTextTags(
            naming: .none, values: ["CrimeGold": "25", "BribeCost": "120"]
        ) { _ in nil }
        #expect(
            tags.fill("You caught me. I'll pay off my bounty. (<CrimeGold> gold)", topic: nil)
                == "You caught me. I'll pay off my bounty. (25 gold)"
        )
        #expect(tags.fill("(<BribeCost> gold)", topic: nil) == "(120 gold)")
        #expect(DialogueTextTags.none
            .fill("(<CrimeGold> gold)", topic: nil) == "(<CrimeGold> gold)")
    }
}
