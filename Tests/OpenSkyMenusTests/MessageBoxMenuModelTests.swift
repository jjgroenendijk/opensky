// One box at a time, selection wrap, answers carry the MESG index, and only a
// one-button box closes on cancel.

@testable import OpenSkyMenus
import Testing

struct MessageBoxMenuModelTests {
    private static func question(token: UInt64?) -> MessageBoxRequest {
        MessageBoxRequest(
            title: nil,
            text: "Sleep?",
            buttons: [
                MessageBoxButton(index: 0, text: "Yes"),
                MessageBoxButton(index: 2, text: "No")
            ],
            token: token
        )
    }

    @Test func queuesBoxesAndAnswersWithTheOriginalIndex() {
        var model = MessageBoxMenuModel()
        let opened = model.enqueue(Self.question(token: 7))
        #expect(opened)
        let opened2 = model.enqueue(MessageBoxRequest(
            title: nil,
            text: "Hi",
            buttons: [],
            token: nil
        ))
        #expect(!opened2)
        model.moveSelection(by: 1)
        let answer = model.accept()
        #expect(answer == MessageBoxAnswer(token: 7, buttonIndex: 2))
        #expect(model.current?.text == "Hi")
        #expect(model.current?.buttons == [MessageBoxButton(index: 0, text: "OK")])
        let answer2 = model.accept()
        #expect(answer2 == MessageBoxAnswer(token: nil, buttonIndex: 0))
        #expect(!model.isOpen)
    }

    @Test func selectionWrapsBothWays() {
        var model = MessageBoxMenuModel()
        model.enqueue(Self.question(token: 1))
        model.moveSelection(by: -1)
        #expect(model.selection == 1)
        model.moveSelection(by: 1)
        #expect(model.selection == 0)
        model.select(row: 5)
        #expect(model.selection == 0)
    }

    @Test func cancelClosesOnlyAOneButtonBox() {
        var model = MessageBoxMenuModel()
        model.enqueue(Self.question(token: 1))
        let answer = model.cancel()
        #expect(answer == nil)
        #expect(model.isOpen)
        var single = MessageBoxMenuModel()
        single.enqueue(MessageBoxRequest(title: nil, text: "Done", buttons: [], token: nil))
        let answer2 = single.cancel()
        #expect(answer2 == MessageBoxAnswer(token: nil, buttonIndex: 0))
    }
}
