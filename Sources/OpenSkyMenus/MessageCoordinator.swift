// HUD notifications, help messages, and message boxes for scripts and
// agent control. The rules live in `NotificationQueue`, `HelpMessageLedger`, and
// `MessageBoxMenuModel`; this shell moves their output to the HUD and the
// overlay. See docs/engine/messages.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyRenderCore
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
    /// The texts of the HUD's world notices, from their string settings.
    var worldNoticeTexts: GameSettingTexts<WorldNoticeText> { get }
    func setHUDHelpMessage(_ text: String?)
    func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool
    func forceCameraMode(firstPerson: Bool) -> Bool
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
    private var frame: UInt64 = 0
    private var nextToken: UInt64 = 1
    /// Engine menus waiting on a button, by token. A token not here is a script's.
    private var choiceHandlers: [UInt64: (Int) -> Void] = [:]
    /// The box the movie was last sent, so a highlight change does not resend it.
    private var movieRequest: MessageBoxRequest?
    private let menuMode: MenuModeController
    weak let world: (any MessageWorld)?

    /// Draws the box with `messagebox.swf`; the overlay stands in while it loads.
    lazy var movie = MenuMovieDriver<Int>(
        movies: movies, hud: hud, label: "message box movie"
    ) { [weak self] in self?.world?.renderer }

    private let movies: SWFMovieSource?
    private let hud: HUDCoordinator?

    /// Call `reloadHelpRecords()` once the world's records are loaded.
    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any MessageWorld)? = nil
    ) {
        self.menuMode = menuMode
        self.movies = movies
        self.hud = hud
        self.world = world
    }

    /// Reads the help counts again, after a save loads.
    public func reloadHelpRecords() {
        help = HelpMessageLedger(records: world?.helpMessageRecords ?? [:])
        world?.setHUDHelpMessage(nil)
    }

    public func tick(time: Double) {
        frame += 1
        for row in movie.tick(now: time) where boxes.isOpen {
            choose(row: row)
        }
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
        case .button(.xButton), .button(.yButton), .pointer, .release: return
        }
        publish()
    }

    /// The cursor goes to the movie, whose buttons take the click.
    public func route(_ event: MenuPointerEvent) {
        guard boxes.isOpen else { return }
        if movie.isLoaded {
            movie.route(event)
        } else if event.phase == .pressed {
            route(.button(.accept))
        }
    }

    public func choose(row: Int) {
        boxes.select(row: row)
        finish(boxes.accept())
        publish()
    }

    /// Shows a MESG from the readout as a notification or as a box, as the
    /// readout asks. No script waits on a box opened here.
    @discardableResult
    public func show(editorID: String, asBox: Bool) -> MessageShowOutcome {
        guard
            let key = world?.messageKey(editorID: editorID),
            let built = world?.buildMessage(key, arguments: [])
        else { return .notFound(editorID) }
        if asBox {
            open(MessageBoxRequest(
                title: built.title,
                text: built.text,
                buttons: built.buttons,
                token: nil
            ))
            return .opened(editorID)
        }
        let posted = notifications.post(
            built.text,
            hold: built.displaySeconds.map(Double.init),
            frame: frame
        )
        return posted ? .posted(editorID) : .noText(editorID)
    }

    /// A box the engine itself asks, such as the perk activate menu. `answer` gets the
    /// picked button's index.
    public func presentChoices(
        title: String?, text: String, buttons: [String], answer: @escaping (Int) -> Void
    ) {
        let token = nextToken
        nextToken += 1
        choiceHandlers[token] = answer
        open(MessageBoxRequest(
            title: title,
            text: text,
            buttons: buttons.enumerated()
                .map { MessageBoxButton(index: $0.offset, text: $0.element) },
            token: token
        ))
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
            if let handler = choiceHandlers.removeValue(forKey: token) {
                handler(answer.buttonIndex)
            } else {
                world?.answerMessage(token: token, buttonIndex: answer.buttonIndex)
            }
        }
        if !boxes.isOpen {
            menuMode.dismiss(Self.identifier)
        }
    }

    private func publish() {
        guard let request = boxes.current else {
            movieRequest = nil
            movie.stop()
            world?.uiScene = .empty
            return
        }
        world?.uiScene = movie.isLoaded ? .empty : presentation?.scene ?? .empty
        guard movie.isLoaded else {
            if movie.session.path == nil {
                startMovie()
            }
            return
        }
        let selection = boxes.selection
        movie.publish { runtime in
            if movieRequest != request {
                MessageBoxMovieBridge.publish(request, runtime: runtime)
            }
            MessageBoxMovieBridge.highlight(row: selection, runtime: runtime)
        }
        movieRequest = request
    }

    private func startMovie() {
        movieRequest = nil
        movie.start(MenuMovie(
            path: MessageBoxMovieBridge.moviePath,
            prepare: { [weak self] runtime in
                MessageBoxMovieBridge.prepare(runtime: runtime) { self?.movie.post($0) }
            },
            activate: MessageBoxMovieBridge.activate,
            didLoad: { [weak self] in self?.publish() }
        ), while: { [weak self] in self?.boxes.isOpen == true })
    }
}

extension MessageCoordinator: PapyrusPresenting {
    @discardableResult
    public func postNotification(_ text: String) -> Bool {
        notifications.post(text, frame: frame)
    }

    @discardableResult
    public func postWorldNotice(_ notice: WorldNotice) -> Bool {
        let texts = world?.worldNoticeTexts ?? .vanilla
        switch WorldNoticeShape(notice, texts: texts) {
        case let .big(big):
            guard let hud else { return false }
            hud.showBigNotice(big)
            return true
        case let .line(text):
            return postNotification(text)
        }
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

/// What one readout `show` did. Only `text` builds the readout line.
nonisolated public enum MessageShowOutcome: Equatable, Sendable {
    case notFound(String)
    case opened(String)
    case posted(String)
    case noText(String)

    public var text: String {
        switch self {
        case let .notFound(editorID): "No message \(editorID)"
        case let .opened(editorID): "Opened \(editorID)"
        case let .posted(editorID): "Posted \(editorID)"
        case let .noText(editorID): "\(editorID) has no text"
        }
    }
}
