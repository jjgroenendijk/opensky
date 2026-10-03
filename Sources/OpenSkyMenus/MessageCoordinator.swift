// HUD notifications, help messages, and message boxes for scripts and the
// sidebar. The rules live in `NotificationQueue`, `HelpMessageLedger`, and
// `MessageBoxMenuModel`; this shell moves their output to the HUD and the
// overlay. See docs/engine/messages.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyScriptingInterface

/// What the message coordinator needs from the app.
public protocol MessageWorld: SWFLayerWorld {
    /// The MESG behind `key`, built with `arguments`. Nil when no MESG matches.
    func buildMessage(_ key: ReferenceKey, arguments: [Float]) -> BuiltMessage?
    /// Resumes the `Message.Show` call that waits on `token`.
    func answerMessage(token: UInt64, buttonIndex: Int)
    /// The persisted help counts; the save carries them.
    var helpMessageRecords: [String: HelpMessageRecord] { get set }
    func showHUDNotification(_ text: String)
    func setHUDHelpMessage(_ text: String?)
    func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool
    func forceCameraMode(firstPerson: Bool) -> Bool
    /// Every MESG editor ID, sorted, for the panel picker.
    var messageEditorIDs: [String] { get }
    func messageKey(editorID: String) -> ReferenceKey?
    /// Receives keys while a box is open.
    var menuInputConsumer: (any MenuInputConsumer)? { get }
}

public final class MessageCoordinator {
    public static let identifier: MenuIdentifier = "MessageBoxMenu"

    public private(set) var notifications = NotificationQueue()
    public private(set) var help = HelpMessageLedger()
    public private(set) var boxes = MessageBoxMenuModel()
    public private(set) var lastAnswer: MessageBoxAnswer?
    /// What the last panel action did, for the readout.
    public var lastPanelOutcome: String?
    private var frame: UInt64 = 0
    private var nextToken: UInt64 = 1
    private let menuMode: MenuModeController
    private(set) weak var world: (any MessageWorld)?

    public init(menuMode: MenuModeController) {
        self.menuMode = menuMode
    }

    public func attach(world: any MessageWorld) {
        self.world = world
        reloadHelpRecords()
    }

    /// Reads the help counts again, after a save loads.
    public func reloadHelpRecords() {
        help = HelpMessageLedger(records: world?.helpMessageRecords ?? [:])
        world?.setHUDHelpMessage(nil)
    }

    public func tick(time: Double) {
        frame += 1
        for entry in notifications.advance(to: time) {
            world?.showHUDNotification(entry.text)
        }
        if help.advance(to: time) {
            world?.setHUDHelpMessage(help.visibleText)
            storeHelpRecords()
        }
    }

    // MARK: - Help events

    /// The player did `event`, such as "Jump", so its help message is done.
    public func noteInputEvent(_ event: String) {
        let wasVisible = help.visibleText
        help.noteEvent(event)
        storeHelpRecords()
        if wasVisible != help.visibleText {
            world?.setHUDHelpMessage(help.visibleText)
        }
    }

    public func resetAllHelpMessages() {
        help.resetAll()
        storeHelpRecords()
        world?.setHUDHelpMessage(nil)
    }

    private func storeHelpRecords() {
        guard world?.helpMessageRecords != help.records else { return }
        world?.helpMessageRecords = help.records
    }

    // MARK: - Message boxes

    /// The open box's overlay, or nil when no box is open.
    public var presentation: MessageBoxPresentation? {
        boxes.current.map { MessageBoxPresentation(request: $0, selection: boxes.selection) }
    }

    public func route(_ event: MenuInputEvent) {
        guard boxes.isOpen else { return }
        switch event {
        case .move(.up), .move(.left): boxes.moveSelection(by: -1)
        case .move(.down), .move(.right): boxes.moveSelection(by: 1)
        case .button(.accept): finish(boxes.accept())
        case .button(.cancel): finish(boxes.cancel())
        case .pointer, .release: return
        }
        publish()
    }

    public func choose(row: Int) {
        boxes.select(row: row)
        finish(boxes.accept())
        publish()
    }

    /// Shows a MESG from the panel as a notification or as a box, as the
    /// panel asks. No script waits on a box opened here.
    @discardableResult
    public func show(editorID: String, asBox: Bool) -> String {
        guard
            let key = world?.messageKey(editorID: editorID),
            let built = world?.buildMessage(key, arguments: [])
        else { return "No message \(editorID)" }
        if asBox {
            open(MessageBoxRequest(
                title: built.title,
                text: built.text,
                buttons: built.buttons,
                token: nil
            ))
            return "Opened \(editorID)"
        }
        let posted = notifications.post(
            built.text,
            hold: built.displaySeconds.map(Double.init),
            frame: frame
        )
        return posted ? "Posted \(editorID)" : "\(editorID) has no text"
    }

    private func open(_ request: MessageBoxRequest) {
        guard boxes.enqueue(request) else { return }
        menuMode.inputConsumer = world?.menuInputConsumer
        menuMode.present(Self.identifier)
        publish()
    }

    private func finish(_ answer: MessageBoxAnswer?) {
        guard let answer else { return }
        lastAnswer = answer
        if let token = answer.token {
            world?.answerMessage(token: token, buttonIndex: answer.buttonIndex)
        }
        if !boxes.isOpen {
            menuMode.dismiss(Self.identifier)
        }
    }

    private func publish() {
        world?.renderer?.uiScene = presentation?.scene ?? .empty
    }
}

extension MessageCoordinator: PapyrusPresenting {
    @discardableResult
    public func postNotification(_ text: String) -> Bool {
        notifications.post(text, frame: frame)
    }

    public func showMessage(
        _ message: ReferenceKey,
        arguments: [Float]
    ) -> PapyrusMessageShowResult {
        guard let built = world?.buildMessage(message, arguments: arguments)
        else { return .notFound }
        guard built.isMessageBox else {
            notifications.post(
                built.text,
                hold: built.displaySeconds.map(Double.init),
                frame: frame
            )
            return .posted
        }
        let token = nextToken
        nextToken += 1
        open(MessageBoxRequest(
            title: built.title,
            text: built.text,
            buttons: built.buttons,
            token: token
        ))
        return .awaitingButton(token: token)
    }

    @discardableResult
    public func showMessageBox(_ text: String) -> Bool {
        open(MessageBoxRequest(title: nil, text: text, buttons: [], token: nil))
        return true
    }

    @discardableResult
    public func showHelpMessage(_ request: PapyrusHelpMessageRequest) -> Bool {
        guard let built = world?.buildMessage(request.message, arguments: []) else { return false }
        return help.show(
            event: request.event,
            text: built.text,
            duration: Double(request.duration),
            interval: Double(request.interval),
            maxTimes: request.maxTimes
        )
    }

    public func resetHelpMessage(event: String) {
        let wasVisible = help.visibleText
        help.reset(event: event)
        storeHelpRecords()
        if wasVisible != help.visibleText {
            world?.setHUDHelpMessage(help.visibleText)
        }
    }

    @discardableResult
    public func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool {
        world?.shakeCamera(source: source, strength: strength, duration: duration) ?? false
    }

    @discardableResult
    public func forceCameraMode(firstPerson: Bool) -> Bool {
        world?.forceCameraMode(firstPerson: firstPerson) ?? false
    }
}
