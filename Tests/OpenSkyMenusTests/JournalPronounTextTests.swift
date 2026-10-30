// The pronoun subtags of the Creation Kit wiki "Text Replacement" page.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import Testing

@Suite("Journal pronoun text")
struct JournalPronounTextTests {
    private func quest() throws -> Quest {
        try QuestFixture.quest(
            fields: QuestFixture.editorID("MQTest")
                + QuestFixture.general(type: 2)
                + QuestFixture.alias(id: 0, name: "Bob")
                + QuestFixture.alias(id: 1, name: "Ann")
        )
    }

    private func naming() -> QuestAliasNaming {
        var naming = QuestAliasNaming(
            name: { _, aliasID in aliasID == 0 ? "Bob" : "Ann" },
            isFemale: { _, aliasID in aliasID == 1 }
        )
        naming.player = AliasFill(name: "Hero", isFemale: true)
        return naming
    }

    @Test
    func pronounTagsFollowTheFillsSex() throws {
        let text = "<Alias=Bob> ate <Alias.PronounPos=Bob> sandwich. "
            + "<Alias.PronounCap=Bob> was happy."
        #expect(try naming()
            .substituting(text, in: quest()) == "Bob ate his sandwich. He was happy.")
        #expect(try naming().substituting("<Alias.PronounObj=Ann>", in: quest()) == "her")
        #expect(try naming().substituting("<Alias.PronounRef=Ann>", in: quest()) == "herself")
    }

    @Test
    func thePlayerNeedsNoAlias() throws {
        #expect(
            try naming().substituting("<Alias=Player> and <Alias.Pronoun=Player>", in: quest())
                == "Hero and she"
        )
    }

    @Test
    func aPronounOfAnUnknownSexStaysAsWritten() throws {
        let naming = QuestAliasNaming { _, _ in "Bob" }
        #expect(try naming
            .substituting("<Alias.Pronoun=Bob>", in: quest()) == "<Alias.Pronoun=Bob>")
    }
}
