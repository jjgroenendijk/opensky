// `Message.Show` number tokens, alias tags, and visible buttons that keep
// their MESG index. Token examples are the Creation Kit wiki's.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyMenus
import Testing

struct MessageTextBuilderTests {
    private typealias Fixture = ESMFixture

    private static func message(
        text: String,
        box: Bool,
        buttons: [String] = []
    ) throws -> GameMessage {
        var fields: [(String, Data)] = [
            ("FULL", Fixture.zstring("Title")), ("DESC", Fixture.zstring(text)),
            ("DNAM", Fixture.u32(box ? 1 : 0)), ("TNAM", Fixture.u32(4))
        ]
        fields += buttons.map { ("ITXT", Fixture.zstring($0)) }
        return try GameMessage(record: Fixture.record("MESG", fields: fields), localized: false)
    }

    @Test func formatsTheWikiExamples() {
        let values: [Float] = [5, 1.1, -0.523456745]
        #expect(values.map { MessageFormat.format("%f", arguments: [$0]) } == [
            "5.0",
            "1.1",
            "-0.523457"
        ])
        #expect(values.map { MessageFormat.format("%.0f", arguments: [$0]) } == ["5", "1", "-1"])
        #expect(values.map { MessageFormat.format("%10.2f", arguments: [$0]) }
            == ["      5.00", "      1.10", "     -0.52"])
    }

    @Test func fillsTokensInOrderAndKeepsPercentSigns() {
        let text = "You've collected %.0f apples and %.0f oranges. %.0f%% done."
        #expect(MessageFormat.format(text, arguments: [0, 10, 20])
            == "You've collected 0 apples and 10 oranges. 20% done.")
        #expect(MessageFormat.format("%.0f and %.0f", arguments: [3]) == "3 and 0")
        #expect(MessageFormat.format("100% sure", arguments: []) == "100% sure")
        #expect(MessageFormat.format("%+.1f", arguments: [2]) == "+2.0")
        #expect(MessageFormat.format("%-4.0f|", arguments: [7]) == "7   |")
        #expect(MessageFormat.format("%04.0f", arguments: [-7]) == "-007")
    }

    @Test func findsUnresolvedTokens() {
        #expect(MessageFormat.hasUnresolvedToken("Bring <Alias=Item>"))
        #expect(MessageFormat.hasUnresolvedToken("Gold: %.0f"))
        #expect(!MessageFormat.hasUnresolvedToken("Done, 100%% sure"))
        #expect(!MessageFormat.hasUnresolvedToken("a < b"))
    }

    @Test func buildsTextWithAliasesAndNumbers() throws {
        let quest = try QuestFixture.quest(
            fields: QuestFixture.editorID("Q") + QuestFixture.alias(id: 0, name: "Thief")
        )
        let builder = MessageTextBuilder(
            strings: nil,
            naming: QuestAliasNaming { _, _ in "Brynjolf" }
        )
        let built = try builder.build(
            Self.message(text: "<Alias=Thief> owes %.0f gold.", box: false),
            arguments: [50],
            quest: quest
        )
        #expect(built.text == "Brynjolf owes 50 gold.")
        #expect(built.title == "Title")
        #expect(built.buttons.isEmpty)
        #expect(built.displaySeconds == 4)
    }

    @Test func hiddenButtonsKeepTheirIndexes() throws {
        let message = try Self.message(text: "Sleep?", box: true, buttons: ["Yes", "Wait", "No"])
        let built = MessageTextBuilder(strings: nil).build(message) { button in
            button.text != .inline("Wait")
        }
        #expect(built.buttons == [
            MessageBoxButton(index: 0, text: "Yes"),
            MessageBoxButton(index: 2, text: "No")
        ])
    }

    @Test func boxWithoutButtonsGetsOK() throws {
        let built = try MessageTextBuilder(strings: nil).build(Self.message(
            text: "Hello",
            box: true
        ))
        #expect(built.buttons == [MessageBoxButton(index: 0, text: "OK")])
    }
}
