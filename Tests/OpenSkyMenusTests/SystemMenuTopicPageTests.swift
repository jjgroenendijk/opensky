// The Help and Installed Content pages: their topic list, the text of one topic, and
// the rows built from help messages and plugin headers.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

struct SystemMenuTopicPageTests {
    private static let topics = [
        SystemMenuTopic(title: "sprinting", text: "Hold Shift."),
        SystemMenuTopic(title: "Attack", text: "Click."),
        SystemMenuTopic(title: "Block", text: "Right click.")
    ]

    @Test func topicsAreSortedByTitleIgnoringCase() {
        let page = SystemMenuTopicPageModel(topics: Self.topics)
        #expect(page.topics.map(\.title) == ["Attack", "Block", "sprinting"])
        #expect(page.openTopic == nil)
    }

    @Test func acceptOpensTheTopicAndCancelReturnsToTheList() {
        var page = SystemMenuTopicPageModel(topics: Self.topics)
        page.handle(.move(.up))
        #expect(page.selectedIndex == 2, "the list wraps")
        #expect(page.handle(.button(.accept)) == nil)
        #expect(page.openTopic?.text == "Hold Shift.")
        #expect(page.handle(.button(.cancel)) == nil)
        #expect(page.openTopic == nil)
        #expect(page.handle(.button(.cancel)) == .back)
    }

    @Test func theMovieOpensATopicByItsIndex() {
        var page = SystemMenuTopicPageModel(topics: Self.topics)
        page.open(1)
        #expect(page.openTopic?.title == "Block")
        page.open(9)
        #expect(page.openTopic?.title == "Block", "an index past the list is ignored")
        page.showList()
        #expect(page.openTopic == nil)
    }

    @Test func theMovieMovesTheSelection() {
        var page = SystemMenuTopicPageModel(topics: Self.topics)
        page.select(2)
        #expect(page.selectedIndex == 2)
        page.select(-1)
        #expect(page.selectedIndex == 2, "an index outside the list is ignored")
    }

    @Test func helpTopicsSkipMessagesWithoutATitle() {
        let messages = [
            BuiltMessage(
                title: "Sprinting",
                text: "Hold [Sprint].",
                buttons: [],
                isMessageBox: false
            ),
            BuiltMessage(title: nil, text: "No title", buttons: [], isMessageBox: false)
        ]
        #expect(SystemMenuTopic.help(messages) == [
            SystemMenuTopic(title: "Sprinting", text: "Hold [Sprint].")
        ])
    }

    @Test func installedContentListsEachPluginWithItsHeader() {
        let plugins = [
            InstalledPlugin(name: "Skyrim.esm"),
            InstalledPlugin(
                name: "Example.esl", author: "Someone", summary: "Adds a thing.",
                masters: ["Skyrim.esm", "Update.esm"]
            )
        ]
        let topics = SystemMenuTopic.installedContent(plugins)
        #expect(topics.map(\.title) == ["Skyrim.esm", "Example.esl"])
        #expect(topics[0].text.isEmpty)
        #expect(topics[1].text == "Author: Someone\nAdds a thing.\nMasters: Skyrim.esm, Update.esm")
    }

    @Test func movieRowsCarryTheIndexTheMovieHandsBack() {
        let rows = SystemMenuMovieBridge.topicRows(Self.topics)
        #expect(rows[1]["text"] == .string("Attack"))
        #expect(rows[1]["index"] == .integer(1))
        #expect(SystemMenuMovieBridge.rowEntries["$HELP"] == .help)
        #expect(SystemMenuMovieBridge.rowEntries["$INSTALLED CONTENT"] == .installedContent)
        #expect(SystemMenuMovieBridge.topicCalls.map(\.populate) == [
            "PopulateHelpTopics", "PopulateCreationClubTopics"
        ])
    }
}
