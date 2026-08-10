// Dialogue menu model (issue #205, roadmap item 17.3): the cursor, the response
// lifecycle and the subtitle the HUD is told to show, with no movie, no
// renderer and no install.
//
// The model is the half of the menu that decides what happens; the movie bridge
// only draws it. So these are the tests that pin behaviour a player would
// notice: the selection stops at the ends rather than wrapping, a chosen line
// cannot be chosen over, and the subtitle goes away when the line does.

@testable import opensky
import Testing

@MainActor
struct DialogueMenuModelTests {
    private func entry(
        _ id: UInt32,
        text: String,
        goodbye: Bool = false
    ) -> DialogueTopicEntry {
        DialogueTopicEntry(
            topic: FormID(id),
            info: FormID(id + 0x1000),
            text: text,
            endsConversation: goodbye
        )
    }

    private func model(_ count: Int = 3) -> DialogueMenuModel {
        DialogueMenuModel(
            speaker: "Belethor",
            speakerKey: nil,
            topics: (0 ..< count).map { entry(UInt32($0 + 1), text: "topic \($0)") }
        )
    }

    @Test
    func opensOnTheFirstTopic() {
        let menu = model()
        #expect(menu.selectedIndex == 0)
        #expect(menu.selectedTopic?.text == "topic 0")
        #expect(menu.state == .topicList)
        #expect(menu.acceptsSelection)
        #expect(menu.subtitle == nil)
    }

    @Test
    func anEmptyListSelectsNothing() {
        let menu = DialogueMenuModel(speaker: "Belethor", speakerKey: nil, topics: [])
        // -1 is the list base's own nothing-selected sentinel, measured on
        // `iSelectedIndex`.
        #expect(menu.selectedIndex == -1)
        #expect(menu.isEmpty)
        #expect(!menu.acceptsSelection)
        #expect(menu.selectedTopic == nil)
    }

    @Test
    func selectionStopsAtBothEndsRatherThanWrapping() {
        var menu = model()
        menu.moveSelection(by: -1)
        #expect(menu.selectedIndex == 0)
        menu.moveSelection(by: 1)
        menu.moveSelection(by: 1)
        menu.moveSelection(by: 1)
        #expect(menu.selectedIndex == 2)
    }

    @Test
    func selectClampsIntoTheRowsThatExist() {
        var menu = model()
        menu.select(99)
        #expect(menu.selectedIndex == 2)
        menu.select(-5)
        #expect(menu.selectedIndex == 0)
    }

    @Test
    func beginningAResponseStopsTheListTakingInput() {
        var menu = model()
        menu.beginResponse(info: FormID(0x2000), runs: ["first line"])
        #expect(menu.state == .response)
        #expect(!menu.acceptsSelection)
        #expect(menu.subtitle == "first line")
        #expect(menu.line?.count == 1)
        #expect(menu.line?.hasMore == false)
    }

    @Test
    func advancingWalksEveryRunThenReportsTheEnd() {
        var menu = model()
        menu.beginResponse(info: FormID(0x2000), runs: ["one", "two", "three"])
        #expect(menu.subtitle == "one")
        // Hoisted out of `#expect`, which captures its operand immutably and so
        // cannot call a `mutating` method inline.
        let toSecond = menu.advanceResponse()
        #expect(toSecond)
        #expect(menu.subtitle == "two")
        #expect(menu.line?.index == 1)
        let toThird = menu.advanceResponse()
        #expect(toThird)
        #expect(menu.subtitle == "three")
        // The last run: the caller's cue to hand the list back or end the
        // conversation, which is why this reports false rather than looping.
        let pastEnd = menu.advanceResponse()
        #expect(!pastEnd)
        #expect(menu.subtitle == "three")
    }

    @Test
    func aResponseWithNoTextIsStillAResponse() {
        var menu = model()
        menu.beginResponse(info: FormID(0x2000), runs: [])
        #expect(menu.state == .response)
        #expect(menu.subtitle == nil)
        // Held in a local because `#expect(menu.line?.count == 0)` is what the
        // autoformatter rewrites into `.isEmpty`, which a run count does not
        // have.
        let runCount = menu.line?.count
        #expect(runCount == 0)
        let advanced = menu.advanceResponse()
        #expect(!advanced)
    }

    @Test
    func handingTheListBackClearsTheSubtitle() {
        var menu = model()
        menu.select(2)
        menu.beginResponse(info: FormID(0x2000), runs: ["said"])
        menu.showTopicList()
        #expect(menu.state == .topicList)
        #expect(menu.subtitle == nil)
        #expect(menu.line == nil)
        // The cursor survives the line, so a conversation comes back where the
        // player left it.
        #expect(menu.selectedIndex == 2)
    }

    @Test
    func aGreetingIsAResponseInItsOwnState() {
        var menu = model()
        menu.beginResponse(
            info: FormID(0x2000),
            runs: ["Some may call this junk."],
            isGreeting: true
        )
        #expect(menu.state == .greeting)
        #expect(!menu.acceptsSelection)
        #expect(menu.subtitle == "Some may call this junk.")
    }

    @Test
    func replacingTopicsReturnsTheCursorToTheTop() {
        var menu = model()
        menu.select(2)
        menu.setTopics([entry(9, text: "follow-up", goodbye: true)])
        #expect(menu.topics.count == 1)
        #expect(menu.selectedIndex == 0)
        #expect(menu.selectedTopic?.endsConversation == true)
    }

    @Test
    func replacingTopicsWithNothingSelectsNothing() {
        var menu = model()
        menu.setTopics([])
        #expect(menu.selectedIndex == -1)
        #expect(!menu.acceptsSelection)
    }
}
