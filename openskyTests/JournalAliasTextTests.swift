// Alias substitution in journal text (issue #184): the `<Alias=Name>` family
// the Creation Kit documents under text replacement, resolved through the #183
// fill table.
//
// The tag syntax is not invented here — `openskycli swf quest-journal --text`
// prints resolved vanilla journal strings, and `<Alias=QuestNameLocation>` is
// one of them verbatim. The quests below are synthetic all the same.

import Foundation
@testable import opensky
import Testing

@Suite("Journal alias text")
struct JournalAliasTextTests {
    private func quest() throws -> Quest {
        try QuestFixture.quest(
            fields: QuestFixture.editorID("MGRArniel01")
                + QuestFixture.general(type: 2)
                + QuestFixture.marker("ANAM")
                + QuestFixture.alias(id: 0, name: "ArnielGane")
                + QuestFixture.alias(id: 1, name: "Cog")
        )
    }

    /// Names every alias by its number, so a test can tell which alias a tag
    /// resolved through rather than only that it resolved.
    private let naming = QuestAliasNaming { _, aliasID in
        aliasID == 0 ? "Arniel Gane" : nil
    }

    @Test
    func replacesAnAliasTagWithTheFilledName() throws {
        let quest = try quest()
        #expect(
            naming.substituting("Speak to <Alias=ArnielGane>.", in: quest)
                == "Speak to Arniel Gane."
        )
    }

    /// The Creation Kit's qualified forms name a different *name* of the same
    /// object. OpenSky has one name per reference, so the qualifier is parsed
    /// only so the tag is still recognized.
    @Test
    func acceptsAQualifiedTagAndMatchesTheNameCaseInsensitively() throws {
        let quest = try quest()
        #expect(
            naming.substituting("<Alias.ShortName=arnielgane> waits.", in: quest)
                == "Arniel Gane waits."
        )
    }

    /// An unresolvable tag survives as written: a visible tag says "this fill
    /// is missing", where deleting it would leave a sentence with a hole in it.
    @Test
    func leavesUnresolvableTagsExactlyAsWritten() throws {
        let quest = try quest()
        #expect(naming.substituting("Find <Alias=Cog>.", in: quest) == "Find <Alias=Cog>.")
        #expect(
            naming.substituting("Find <Alias=NoSuchAlias>.", in: quest)
                == "Find <Alias=NoSuchAlias>."
        )
        #expect(
            QuestAliasNaming.none.substituting("Find <Alias=ArnielGane>.", in: quest)
                == "Find <Alias=ArnielGane>."
        )
    }

    /// A different replacement family — a global, an actor value — is not an
    /// alias tag and is left alone.
    @Test
    func ignoresNonAliasTagsAndMalformedOnes() throws {
        let quest = try quest()
        #expect(
            naming.substituting("<Global=GoldValue> septims", in: quest)
                == "<Global=GoldValue> septims"
        )
        #expect(naming.substituting("2 < 3 and 4 > 1", in: quest) == "2 < 3 and 4 > 1")
        #expect(
            naming.substituting("unterminated <Alias=ArnielGane", in: quest)
                == "unterminated <Alias=ArnielGane"
        )
        #expect(naming.substituting("plain text", in: quest) == "plain text")
    }

    @Test
    func replacesEveryOccurrence() throws {
        let quest = try quest()
        #expect(
            naming.substituting(
                "<Alias=ArnielGane> asked. I found <Alias=ArnielGane>.", in: quest
            ) == "Arniel Gane asked. I found Arniel Gane."
        )
    }
}
