// Notifications show in order, hold, respect the visible cap, and drop a
// repeat posted in the same frame.

@testable import OpenSkyMenus
import Testing

struct NotificationQueueTests {
    @Test func showsInOrderUpToTheCap() {
        var queue = NotificationQueue()
        for (index, text) in ["a", "b", "c", "d"].enumerated() {
            queue.post(text, frame: UInt64(index))
        }
        let shownNow = queue.advance(to: 0)
        #expect(shownNow.map(\.text) == ["a", "b", "c"])
        #expect(queue.waiting.map(\.text) == ["d"])
        let shownNow2 = queue.advance(to: 1)
        #expect(shownNow2.isEmpty)
        let shownNow3 = queue.advance(to: NotificationQueue.defaultHold)
        #expect(shownNow3.map(\.text) == ["d"])
        #expect(queue.visible.map(\.text) == ["d"])
    }

    @Test func dropsSameFrameRepeatsAndEmptyText() {
        var queue = NotificationQueue()
        let posted = queue.post("Quest started", frame: 1)
        #expect(posted)
        let posted2 = queue.post("Quest started", frame: 1)
        #expect(!posted2)
        let posted3 = queue.post("Quest started", frame: 2)
        #expect(posted3)
        let posted4 = queue.post("", frame: 3)
        #expect(!posted4)
        #expect(queue.postedCount == 2)
        #expect(queue.droppedCount == 1)
    }

    @Test func entryHoldsForItsOwnTime() {
        var queue = NotificationQueue()
        queue.post("short", hold: 1, frame: 0)
        _ = queue.advance(to: 0)
        _ = queue.advance(to: 0.9)
        #expect(queue.visible.count == 1)
        _ = queue.advance(to: 1)
        #expect(queue.visible.isEmpty)
    }
}
