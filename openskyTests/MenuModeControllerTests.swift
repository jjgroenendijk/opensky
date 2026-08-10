// Menu-mode controller (todo 8.1.2, extended by issue #205): transitions fire
// onModeChange exactly when the input route or the world-sim pause gate moves,
// the routing decision follows the stack, routed menu events reach an attached
// consumer only in menu mode, and a menu presented under
// `MenuWorldPolicy.leavesWorldRunning` captures input without stopping the
// world. Pure reference type, no AppKit or GPU.

@testable import opensky
import Testing

@MainActor
private final class SpyMenuConsumer: MenuInputConsumer {
    private(set) var events: [MenuInputEvent] = []

    func handleMenuInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}

@MainActor
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
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        #expect(controller.present("InventoryMenu"))
        #expect(controller.isMenuMode)
        #expect(controller.isWorldSimPaused)
        #expect(controller.currentRoute == .menu)
        #expect(controller.topMenu == "InventoryMenu")
        #expect(changes.count == 1)
        #expect(changes.first?.route == .menu)
        #expect(changes.first?.paused == true)
    }

    @Test
    func stackingASecondMenuDoesNotRefireModeChange() {
        let controller = MenuModeController()
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.present("InventoryMenu")
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        controller.present("Console")
        // Still menu mode both before and after -> no boundary crossing.
        #expect(changes.isEmpty)
        #expect(controller.topMenu == "Console")
    }

    @Test
    func duplicatePresentIsRejectedWithoutModeChange() {
        let controller = MenuModeController()
        controller.present("InventoryMenu")
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        #expect(!controller.present("InventoryMenu"))
        #expect(changes.isEmpty)
    }

    @Test
    func dismissingLastMenuResumesGameplay() {
        let controller = MenuModeController()
        controller.present("InventoryMenu")
        controller.present("Console")
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        #expect(controller.dismissTop() == "Console")
        // Still one menu open -> no boundary crossing yet.
        #expect(changes.isEmpty)
        #expect(controller.isWorldSimPaused)
        #expect(controller.dismissTop() == "InventoryMenu")
        #expect(changes.count == 1)
        #expect(changes.first?.route == .world)
        #expect(changes.first?.paused == false)
        #expect(!controller.isWorldSimPaused)
        #expect(controller.currentRoute == .world)
    }

    @Test
    func dismissByNameResumesOnlyWhenStackEmpties() {
        let controller = MenuModeController()
        controller.present("A")
        controller.present("B")
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        #expect(controller.dismiss("A"))
        #expect(changes.isEmpty)
        #expect(controller.isMenuMode)
        #expect(controller.dismiss("B"))
        #expect(changes.count == 1)
        #expect(changes.first?.route == .world)
    }

    @Test
    func dismissAllResumesGameplay() {
        let controller = MenuModeController()
        controller.present("A")
        controller.present("B")
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        controller.dismissAll()
        #expect(changes.count == 1)
        #expect(changes.first?.route == .world)
        #expect(changes.first?.paused == false)
        #expect(!controller.isMenuMode)
    }

    @Test
    func dismissAllInGameplayIsNoOp() {
        let controller = MenuModeController()
        var fired = false
        controller.onModeChange = { _, _ in fired = true }
        controller.dismissAll()
        #expect(!fired)
    }

    // MARK: - Per-menu world policy (issue #205)

    @Test
    func dialogueMenuCapturesInputWithoutPausingTheWorld() {
        let controller = MenuModeController()
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        #expect(controller.present("Dialogue Menu", policy: .leavesWorldRunning))
        #expect(controller.isMenuMode)
        #expect(controller.currentRoute == .menu)
        // The whole point of the milestone: voice, facing and lip sync all
        // advance on the world clock while the topic list is up.
        #expect(!controller.isWorldSimPaused)
        #expect(changes.count == 1)
        #expect(changes.first?.route == .menu)
        #expect(changes.first?.paused == false)
    }

    @Test
    func menusWithoutAPolicyStillPause() {
        let controller = MenuModeController()
        controller.present("InventoryMenu")
        #expect(controller.isWorldSimPaused)
        #expect(controller.policy(of: "InventoryMenu") == .pausesWorld)
    }

    @Test
    func aPausingMenuOverAConversationPausesAndUnpauses() {
        let controller = MenuModeController()
        controller.present("Dialogue Menu", policy: .leavesWorldRunning)
        var changes: [(route: InputRoute, paused: Bool)] = []
        controller.onModeChange = { route, paused in changes.append((route, paused)) }
        controller.present("SystemMenu")
        // The route did not move — it was already menu — but the pause did, and
        // a listener that only watched the route would have missed it.
        #expect(controller.isWorldSimPaused)
        #expect(changes.count == 1)
        #expect(changes.first?.route == .menu)
        #expect(changes.first?.paused == true)
        controller.dismiss("SystemMenu")
        #expect(!controller.isWorldSimPaused)
        #expect(controller.isMenuMode)
        #expect(changes.count == 2)
        #expect(changes.last?.paused == false)
    }

    @Test
    func closingAConversationLeavesNoPolicyBehind() {
        let controller = MenuModeController()
        controller.present("Dialogue Menu", policy: .leavesWorldRunning)
        controller.dismiss("Dialogue Menu")
        // Re-presented without a policy, the same name must pause: a stale
        // entry would silently make the next menu of that name non-pausing.
        controller.present("Dialogue Menu")
        #expect(controller.isWorldSimPaused)
    }

    @Test
    func dismissAllClearsEveryPolicy() {
        let controller = MenuModeController()
        controller.present("Dialogue Menu", policy: .leavesWorldRunning)
        controller.present("SystemMenu")
        controller.dismissAll()
        #expect(!controller.isMenuMode)
        #expect(!controller.isWorldSimPaused)
        controller.present("Dialogue Menu")
        #expect(controller.isWorldSimPaused)
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
