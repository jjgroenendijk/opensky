// Scripts reach the HUD and the message box through the coordinator: a box
// pauses the world and answers its waiting call, notifications reach the HUD
// in order, and help counts persist through the world port.

import OpenSkyFormatsESM
@testable import OpenSkyMenus
import OpenSkyRendering
import OpenSkyScriptingInterface
import Testing

@MainActor
final class FakeMessageWorld: MessageWorld, MenuInputConsumer {
    var renderer: Renderer? {
        nil
    }

    var messages: [ReferenceKey: BuiltMessage] = [:]
    var answers: [(UInt64, Int)] = []
    var helpMessageRecords: [String: HelpMessageRecord] = [:]
    var hudLines: [String] = []
    var hudHelp: [String?] = []
    var events: [MenuInputEvent] = []

    func buildMessage(_ key: ReferenceKey, arguments: [Float]) -> BuiltMessage? {
        messages[key]
    }

    func answerMessage(token: UInt64, buttonIndex: Int) {
        answers.append((token, buttonIndex))
    }

    func showHUDNotification(_ text: String) {
        hudLines.append(text)
    }

    func setHUDHelpMessage(_ text: String?) {
        hudHelp.append(text)
    }

    func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool {
        true
    }

    func forceCameraMode(firstPerson: Bool) -> Bool {
        false
    }

    var messageEditorIDs: [String] {
        ["Note", "Question"]
    }

    func messageKey(editorID: String) -> ReferenceKey? {
        switch editorID {
        case "Question": MessageCoordinatorTests.question
        case "Note": MessageCoordinatorTests.note
        default: nil
        }
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        self
    }

    func handleMenuInput(_ event: MenuInputEvent) {
        events.append(event)
    }
}

@MainActor
struct MessageCoordinatorTests {
    static let question = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x10)
    static let note = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x11)

    static func world() -> FakeMessageWorld {
        let world = FakeMessageWorld()
        world.messages[question] = BuiltMessage(
            title: "Wait",
            text: "Sleep here?",
            buttons: [
                MessageBoxButton(index: 0, text: "Yes"),
                MessageBoxButton(index: 2, text: "No")
            ],
            isMessageBox: true
        )
        world.messages[note] = BuiltMessage(
            title: nil,
            text: "Gold: 5",
            buttons: [],
            isMessageBox: false
        )
        return world
    }

    @Test func boxPausesTheWorldAndAnswersItsCaller() {
        let menuMode = MenuModeController()
        let world = Self.world()
        let messages = MessageCoordinator(menuMode: menuMode)
        messages.attach(world: world)

        let result = messages.showMessage(Self.question, arguments: [])
        #expect(result == .awaitingButton(token: 1))
        #expect(menuMode.topMenu == MessageCoordinator.identifier)
        #expect(menuMode.inputConsumer === world)

        messages.route(.button(.cancel))
        #expect(messages.boxes.isOpen)
        messages.route(.move(.down))
        messages.route(.button(.accept))
        #expect(world.answers.map(\.0) == [1])
        #expect(world.answers.map(\.1) == [2])
        #expect(menuMode.topMenu == nil)
    }

    @Test func notificationsReachTheHUDInOrder() {
        let world = Self.world()
        let messages = MessageCoordinator(menuMode: MenuModeController())
        messages.attach(world: world)

        #expect(messages.showMessage(Self.note, arguments: []) == .posted)
        messages.postNotification("Second")
        #expect(messages
            .showMessage(.plugin(name: "skyrim.esm", objectID: 0x99), arguments: []) == .notFound)
        messages.tick(time: 0)
        #expect(world.hudLines == ["Gold: 5", "Second"])
    }

    @Test func helpCountsPersistThroughTheWorld() {
        let world = Self.world()
        let messages = MessageCoordinator(menuMode: MenuModeController())
        messages.attach(world: world)
        let request = PapyrusHelpMessageRequest(
            message: Self.note, event: "Jump", duration: 0, interval: 0, maxTimes: 1
        )

        #expect(messages.showHelpMessage(request))
        messages.tick(time: 0)
        #expect(world.hudHelp.last == "Gold: 5")
        messages.noteInputEvent("jump")
        #expect(world.hudHelp.last == .some(nil))
        #expect(world.helpMessageRecords["jump"] == HelpMessageRecord(timesShown: 1, isDone: true))
        #expect(!messages.showHelpMessage(request))

        messages.resetHelpMessage(event: "Jump")
        #expect(world.helpMessageRecords.isEmpty)
    }

    @Test func panelShowsAnyMessageEitherWayAndReadsBack() {
        let menuMode = MenuModeController()
        let world = Self.world()
        let messages = MessageCoordinator(menuMode: menuMode)
        messages.attach(world: world)

        #expect(messages.show(editorID: "Note", asBox: false) == "Posted Note")
        #expect(messages.show(editorID: "Missing", asBox: false) == "No message Missing")
        #expect(messages.show(editorID: "Question", asBox: true) == "Opened Question")
        messages.tick(time: 0)
        let text = MessageReadout.text(for: messages.snapshot(lastOutcome: nil))
        #expect(text.contains("Notifications: 1 shown, 0 waiting"))
        #expect(text.contains("Box: Wait"))
        messages.choose(row: 1)
        #expect(world.answers.isEmpty)
        #expect(messages.lastAnswer?.buttonIndex == 2)
    }
}
