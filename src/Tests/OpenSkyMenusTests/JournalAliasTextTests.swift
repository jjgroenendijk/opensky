// Alias substitution in journal text: the `<Alias=Name>` family from the
// Creation Kit text replacement page. Vanilla journal strings contain
// `<Alias=QuestNameLocation>` verbatim; the quests below are synthetic.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import OpenSkyMenusInterface
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

    /// An alias with no fill shows `sInvalidTagString`, as the game does. Naming with
    /// no session behind it leaves the tag as written.
    @Test
    func showsTheInvalidTagTextForAMissingFill() throws {
        let quest = try quest()
        #expect(naming.substituting("Find <Alias=Cog>.", in: quest) == "Find [...].")
        #expect(
            naming.substituting("Find <Alias=NoSuchAlias>.", in: quest) == "Find [...]."
        )
        #expect(
            QuestAliasNaming.none.substituting("Find <Alias=ArnielGane>.", in: quest)
                == "Find <Alias=ArnielGane>."
        )
    }

    /// A family OpenSky does not read, such as an actor value, is left alone.
    @Test
    func ignoresUnreadTagsAndMalformedOnes() throws {
        let quest = try quest()
        #expect(
            naming.substituting("<ActorValue=Health> left", in: quest)
                == "<ActorValue=Health> left"
        )
        #expect(naming.substituting("2 < 3 and 4 > 1", in: quest) == "2 < 3 and 4 > 1")
        #expect(
            naming.substituting("unterminated <Alias=ArnielGane", in: quest)
                == "unterminated <Alias=ArnielGane"
        )
        #expect(naming.substituting("plain text", in: quest) == "plain text")
    }

    @Test
    func replacesAGlobalTagWithItsValue() throws {
        let quest = try quest()
        var naming = naming
        naming.global = { ["FFR04NirnCount": 3, "Price": 2.5, "Timer": 0.5][$0] }
        #expect(
            naming.substituting("(<Global=FFR04NirnCount>/20) <Global=Price>", in: quest)
                == "(3/20) 2.50"
        )
        #expect(naming.substituting("<Global.Time=Timer>", in: quest) == "30 Minutes")
        #expect(naming.substituting("<Global=Missing>", in: quest) == "[...]")
        #expect(naming.substituting("<Global.Odd=Price>", in: quest) == "<Global.Odd=Price>")
    }

    @Test
    func readsACalendarGlobalAsADate() throws {
        let quest = try quest()
        var naming = naming
        // Days past the 17th of Last Seed 4E 201, at 15:00.
        naming.global = { $0 == "Due" ? 1.625 : nil }
        #expect(naming.substituting("<Global.Day=Due>", in: quest) == "18")
        #expect(naming.substituting("<Global.MonthWord=Due>", in: quest) == "Last Seed")
        #expect(naming.substituting("<Global.WeekDay=Due>", in: quest) == "Morndas")
        #expect(naming.substituting("<Global.TimeSpan=Due>", in: quest) == "Afternoon")
        #expect(naming.substituting("<Global.Hour12=Due> <Global.Meridiem=Due>", in: quest)
            == "3 PM")
    }

    @Test
    func timerTagsAndSpansFollowTheirSettings() {
        #expect(TextReplacementText.span(atHour: 23.5) == .midnight)
        #expect(TextReplacementText.span(atHour: 0.5) == .midnight)
        #expect(TextReplacementText.span(atHour: 6) == .sunrise)
        #expect(TextReplacementText.span(atHour: 21) == .evening)
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
