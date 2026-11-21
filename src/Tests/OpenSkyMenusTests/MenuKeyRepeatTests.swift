// A held menu direction repeats on the game's timing: 0.5 then every 0.1 seconds,
// and 0.2 then every 0.075 seconds in the journal.

@testable import OpenSkyMenus
import OpenSkyMenusInterface
import Testing

@MainActor
private final class RepeatSpy: MenuInputConsumer {
    private(set) var events: [MenuInputEvent] = []

    func handleMenuInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}

@MainActor
struct MenuKeyRepeatTests {
    @Test func aHeldDirectionRepeatsAfterTheDelayThenAtTheInterval() {
        var repeater = MenuKeyRepeat()
        repeater.note(.move(.down))
        let due = [0, 0.4, 0.5, 0.55, 0.6, 0.7].map {
            repeater.due(now: $0, timing: .standard)
        }
        #expect(due == [nil, nil, .down, nil, .down, .down])
        repeater.note(.release(.down))
        #expect(repeater.due(now: 2, timing: .standard) == nil)
    }

    @Test func releasingAnotherDirectionKeepsTheHeldOne() {
        var repeater = MenuKeyRepeat()
        repeater.note(.move(.up))
        repeater.note(.release(.down))
        _ = repeater.due(now: 0, timing: .standard)
        #expect(repeater.due(now: 0.5, timing: .standard) == .up)
    }

    @Test func theJournalRepeatsFaster() {
        let controller = MenuModeController()
        let spy = RepeatSpy()
        controller.inputConsumer = spy
        controller.present(.journalMenu)
        controller.routeMenuInput(.move(.down))
        for now in [0, 0.2, 0.275] {
            controller.repeatHeldDirection(now: now)
        }
        #expect(spy.events == [.move(.down), .move(.down), .move(.down)])
    }

    @Test func closingTheLastMenuForgetsTheHeldDirection() {
        let controller = MenuModeController()
        let spy = RepeatSpy()
        controller.inputConsumer = spy
        controller.present("InventoryMenu")
        controller.routeMenuInput(.move(.down))
        controller.dismiss("InventoryMenu")
        controller.repeatHeldDirection(now: 0)
        controller.present("InventoryMenu")
        controller.repeatHeldDirection(now: 0.1)
        controller.repeatHeldDirection(now: 1)
        #expect(spy.events == [.move(.down)])
    }
}
