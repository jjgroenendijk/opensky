// Menu-mode controller (todo 8.1.2): mode transitions fire onModeChange exactly
// on the gameplay <-> menu boundary, the input-routing decision follows the
// stack, and routed menu events reach an attached consumer only in menu mode.
// Pure reference type, no AppKit or GPU.

@testable import opensky
import Testing

private final class SpyMenuConsumer: MenuInputConsumer {
    private(set) var events: [MenuInputEvent] = []

    func handleMenuInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}

struct MenuModeControllerTests {
    @Test
    func startsInGameplay() {
        let controller = MenuModeController()
        #expect(!controller.isMenuMode)
        #expect(!controller.isWorldSimPaused)
        #expect(controller.currentRoute == .world)
        #expect(controller.topMenu == nil)
    }

    @Test
    func presentEntersMenuModeAndPauses() {
        let controller = MenuModeController()
        var changes: [Bool] = []
        controller.onModeChange = { changes.append($0) }
        #expect(controller.present("InventoryMenu"))
        #expect(controller.isMenuMode)
        #expect(controller.isWorldSimPaused)
        #expect(controller.currentRoute == .menu)
        #expect(controller.topMenu == "InventoryMenu")
        #expect(changes == [true])
    }

    @Test
    func stackingASecondMenuDoesNotRefireModeChange() {
        let controller = MenuModeController()
        var changes: [Bool] = []
        controller.present("InventoryMenu")
        controller.onModeChange = { changes.append($0) }
        controller.present("Console")
        // Still menu mode both before and after -> no boundary crossing.
        #expect(changes.isEmpty)
        #expect(controller.topMenu == "Console")
    }

    @Test
    func duplicatePresentIsRejectedWithoutModeChange() {
        let controller = MenuModeController()
        controller.present("InventoryMenu")
        var changes: [Bool] = []
        controller.onModeChange = { changes.append($0) }
        #expect(!controller.present("InventoryMenu"))
        #expect(changes.isEmpty)
    }

    @Test
    func dismissingLastMenuResumesGameplay() {
        let controller = MenuModeController()
        controller.present("InventoryMenu")
        controller.present("Console")
        var changes: [Bool] = []
        controller.onModeChange = { changes.append($0) }
        #expect(controller.dismissTop() == "Console")
        // Still one menu open -> no boundary crossing yet.
        #expect(changes.isEmpty)
        #expect(controller.isWorldSimPaused)
        #expect(controller.dismissTop() == "InventoryMenu")
        #expect(changes == [false])
        #expect(!controller.isWorldSimPaused)
        #expect(controller.currentRoute == .world)
    }

    @Test
    func dismissByNameResumesOnlyWhenStackEmpties() {
        let controller = MenuModeController()
        controller.present("A")
        controller.present("B")
        var changes: [Bool] = []
        controller.onModeChange = { changes.append($0) }
        #expect(controller.dismiss("A"))
        #expect(changes.isEmpty)
        #expect(controller.isMenuMode)
        #expect(controller.dismiss("B"))
        #expect(changes == [false])
    }

    @Test
    func dismissAllResumesGameplay() {
        let controller = MenuModeController()
        controller.present("A")
        controller.present("B")
        var changes: [Bool] = []
        controller.onModeChange = { changes.append($0) }
        controller.dismissAll()
        #expect(changes == [false])
        #expect(!controller.isMenuMode)
    }

    @Test
    func dismissAllInGameplayIsNoOp() {
        let controller = MenuModeController()
        var fired = false
        controller.onModeChange = { _ in fired = true }
        controller.dismissAll()
        #expect(!fired)
    }

    @Test
    func routingSwallowsMenuInputInGameplay() {
        let controller = MenuModeController()
        let consumer = SpyMenuConsumer()
        controller.inputConsumer = consumer
        #expect(!controller.routeMenuInput(.button(.accept)))
        #expect(consumer.events.isEmpty)
    }

    @Test
    func routingForwardsMenuInputInMenuMode() {
        let controller = MenuModeController()
        let consumer = SpyMenuConsumer()
        controller.inputConsumer = consumer
        controller.present("InventoryMenu")
        #expect(controller.routeMenuInput(.move(.down)))
        #expect(controller.routeMenuInput(.button(.accept)))
        #expect(consumer.events == [.move(.down), .button(.accept)])
    }

    @Test
    func routingReportsCaptureEvenWithoutConsumer() {
        let controller = MenuModeController()
        controller.present("InventoryMenu")
        // No consumer attached: the event is swallowed but menu mode still owns
        // (captures) it, so world input must not see it.
        #expect(controller.routeMenuInput(.move(.up)))
    }
}
