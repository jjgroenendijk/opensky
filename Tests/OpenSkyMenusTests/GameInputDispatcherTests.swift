// The input path the keyboard and the agent share: world actions reach the
// camera input, and a menu turns movement into menu events.

@testable import OpenSkyMenus
import OpenSkyRendering
import Testing

@MainActor
private final class SpyMenuConsumer: MenuInputConsumer {
    private(set) var events: [MenuInputEvent] = []

    func handleMenuInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}

@MainActor
struct GameInputDispatcherTests {
    private let input = CameraInputState()
    private let menuMode = MenuModeController()

    private var dispatcher: GameInputDispatcher {
        GameInputDispatcher(input: input, menuMode: menuMode)
    }

    @Test func heldActionsHoldUntilReleased() {
        dispatcher.apply(.forward, .press)
        dispatcher.apply(.block, .press)
        let held = input.makeInput(dt: 0.1)
        #expect(held.moveForward == 1)
        #expect(held.block)
        dispatcher.apply(.forward, .release)
        dispatcher.apply(.block, .release)
        let released = input.makeInput(dt: 0.1)
        #expect(released.moveForward == 0)
        #expect(!released.block)
    }

    @Test func oneShotActionsFireOnPressOnly() {
        dispatcher.apply(.jump, .release)
        #expect(!input.makeInput(dt: 0.1).jump)
        dispatcher.apply(.jump, .press)
        #expect(input.makeInput(dt: 0.1).jump)
        dispatcher.apply(.activate, .press)
        #expect(input.consumeActivation())
    }

    @Test func attackPressesAndHolds() {
        dispatcher.apply(.attack, .press)
        let pressed = input.makeInput(dt: 0.1)
        #expect(pressed.attack)
        #expect(pressed.attackHeld)
        dispatcher.apply(.attack, .release)
        #expect(!input.makeInput(dt: 0.1).attackHeld)
    }

    @Test func menuOpenersCallTheirMenus() {
        var opened: [String] = []
        let dispatcher = GameInputDispatcher(
            input: input,
            menuMode: menuMode,
            openJournal: { opened.append("journal") },
            openInventory: { opened.append("inventory") }
        )
        dispatcher.apply(.inventory, .press)
        dispatcher.apply(.journal, .press)
        #expect(opened == ["inventory", "journal"])
    }

    @Test func aMenuTurnsMovementIntoMenuEventsAndSwallowsTheRest() {
        let consumer = SpyMenuConsumer()
        menuMode.inputConsumer = consumer
        menuMode.present(MenuIdentifier("InventoryMenu"))
        #expect(dispatcher.apply(.forward, .press) == .menu(.move(.up)))
        #expect(dispatcher.apply(.menuDown, .release) == .menu(.release(.down)))
        #expect(dispatcher.apply(.menuCancel, .press) == .menu(.button(.cancel)))
        #expect(dispatcher.apply(.jump, .press) == .swallowed)
        #expect(consumer.events == [.move(.up), .release(.down), .button(.cancel)])
        #expect(input.makeInput(dt: 0.1).moveForward == 0)
    }

    @Test func menuActionsDoNothingWithoutAMenu() {
        #expect(dispatcher.apply(.menuAccept, .press) == .noMenu)
    }

    @Test func everyActionNameRoundTrips() {
        for action in GameInputAction.allCases {
            #expect(GameInputAction(rawValue: action.rawValue) == action)
        }
    }
}
