// The help topic screen. A topic is a MESG record whose editor ID starts with "Help"
// and ends with "Long", such as `HelpAlchemyLong` (CK wiki "Message").
// See docs/engine/messages.md#help-topics.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyRendering

/// One help topic's text.
nonisolated public struct HelpTopic: Equatable, Sendable {
    public var editorID: String
    public var title: String
    public var text: String

    public init(editorID: String, title: String, text: String) {
        self.editorID = editorID
        self.title = title
        self.text = text
    }

    /// True for the editor IDs of the help screen's long topics.
    public static func isTopic(editorID: String) -> Bool {
        editorID.hasPrefix("Help") && editorID.hasSuffix("Long")
    }
}

/// What the help screen needs from the app.
public protocol TutorialMenuWorld: MenuScreenWorld {
    func helpTopic(_ editorID: String) -> HelpTopic?
    /// Every help topic's editor ID, sorted.
    var helpTopicEditorIDs: [String] { get }
    /// The key bound to a controlmap user event, such as "E" for "Activate".
    func buttonName(forUserEvent event: String) -> String?
}

public final class TutorialMenuCoordinator: MenuScreen<Never> {
    public static let identifier: MenuIdentifier = "Tutorial Menu"
    public static let hint = "W/S: scroll   Tab or Esc: close"

    public private(set) var topic: HelpTopic?
    private var panelLine = 0
    private weak var world: (any TutorialMenuWorld)?

    public init(
        menuMode: MenuModeController,
        movies: SWFMovieSource? = nil,
        hud: HUDCoordinator? = nil,
        world: (any TutorialMenuWorld)? = nil
    ) {
        self.world = world
        super.init(
            identifier: Self.identifier, movieReadsKeys: true, menuMode: menuMode,
            layer: (movies, hud), world: world
        )
    }

    @discardableResult
    public func open(topic editorID: String) -> Bool {
        guard !isOpen else { return false }
        guard let topic = world?.helpTopic(editorID) else {
            lastResult = "Not opened: no topic \(editorID)"
            return false
        }
        self.topic = topic
        panelLine = 0
        lastResult = "Topic: \(topic.title)"
        present(
            path: TutorialMenuMovieBridge.moviePath,
            prepare: { [weak self] runtime in
                TutorialMenuMovieBridge.prepare(runtime: runtime) { event in
                    self?.world?.buttonName(forUserEvent: event)
                } onClose: {
                    self?.close()
                }
            },
            activate: TutorialMenuMovieBridge.activate(runtime:)
        )
        return true
    }

    @discardableResult
    public func openFirstTopic() -> Bool {
        guard let first = world?.helpTopicEditorIDs.first else {
            lastResult = "Not opened: no help topics"
            return false
        }
        return open(topic: first)
    }

    override func handleKey(_ event: MenuInputEvent) {
        switch event {
        case .move(.up): panelLine = max(0, panelLine - 1)
        case .move(.down): panelLine = min(panelLine + 1, max(0, topicLines.count - 1))
        case .button(.cancel), .button(.accept): close()
        default: return
        }
    }

    override func didClose() {
        topic = nil
    }

    override func publishMovie(_ runtime: SWFMovieRuntime) {
        guard let topic else { return }
        TutorialMenuMovieBridge.publish(title: topic.title, text: topic.text, runtime: runtime)
    }

    private var topicLines: [String] {
        SWFEditText.stripHTML(topic?.text ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    override var panel: MenuTextPanel {
        MenuTextPanel(
            title: topic?.title ?? "",
            lines: Array(topicLines.dropFirst(panelLine)),
            hint: Self.hint
        )
    }
}
