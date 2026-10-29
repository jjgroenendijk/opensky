// The Help and Installed Content pages of the system menu: a list of topics, and
// the text of the one the player opened. See docs/engine/system-menu.md#help-and-installed-content.

import Foundation
import OpenSkyGameData

/// One row of the Help or Installed Content page, and the text it opens.
nonisolated public struct SystemMenuTopic: Equatable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

/// Where the Help and Installed Content pages read their topics. The app answers
/// from the load order; without game data both lists are empty.
@MainActor
public protocol SystemMenuTopicSource: AnyObject {
    func systemMenuTopics(_ page: SystemMenuPage) -> [SystemMenuTopic]
}

nonisolated public struct SystemMenuTopicPageModel: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case back
    }

    /// In the order the movie shows them: sorted by title, case ignored.
    public let topics: [SystemMenuTopic]
    public private(set) var selectedIndex = 0
    /// The topic whose text is shown; nil while the list is shown.
    public private(set) var openIndex: Int?

    public init(topics: [SystemMenuTopic]) {
        self.topics = Self.sorted(topics)
    }

    /// The movie sorts its list by title the same way after the engine fills it.
    public static func sorted(_ topics: [SystemMenuTopic]) -> [SystemMenuTopic] {
        topics.enumerated().sorted { lhs, rhs in
            let order = lhs.element.title.caseInsensitiveCompare(rhs.element.title)
            return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
        }.map(\.element)
    }

    public var openTopic: SystemMenuTopic? {
        openIndex.flatMap { topics.indices.contains($0) ? topics[$0] : nil }
    }

    /// The movie moved its own list.
    public mutating func select(_ index: Int) {
        guard topics.indices.contains(index) else { return }
        selectedIndex = index
    }

    /// The movie opened a topic itself.
    public mutating func open(_ index: Int) {
        guard topics.indices.contains(index) else { return }
        selectedIndex = index
        openIndex = index
    }

    public mutating func showList() {
        openIndex = nil
    }

    /// Cancel on a topic's text goes back to the list; on the list it leaves the page.
    @discardableResult
    public mutating func handle(_ event: MenuInputEvent) -> Action? {
        if openIndex != nil {
            if event == .button(.cancel) || event == .button(.accept) {
                openIndex = nil
            }
            return nil
        }
        switch event {
        case .move(.up) where !topics.isEmpty:
            selectedIndex = (selectedIndex + topics.count - 1) % topics.count
        case .move(.down) where !topics.isEmpty:
            selectedIndex = (selectedIndex + 1) % topics.count
        case .button(.accept):
            open(selectedIndex)
        case .button(.cancel):
            return .back
        default:
            break
        }
        return nil
    }
}

nonisolated extension SystemMenuTopic {
    /// One topic per help message, titled by its `FULL`, with its `DESC` as the text.
    public static func help(_ messages: [BuiltMessage]) -> [SystemMenuTopic] {
        messages.compactMap { message in
            guard let title = message.title, !title.isEmpty else { return nil }
            return SystemMenuTopic(title: title, text: message.text)
        }
    }

    /// One topic per active plugin, titled by its file name. The game names a Creation
    /// from data outside the install, so OpenSky shows what the plugin header holds.
    public static func installedContent(_ plugins: [InstalledPlugin]) -> [SystemMenuTopic] {
        plugins.map { plugin in
            let lines = [
                plugin.author.map { "Author: \($0)" },
                plugin.summary,
                plugin.masters.isEmpty ? nil : "Masters: " + plugin.masters.joined(separator: ", ")
            ]
            return SystemMenuTopic(
                title: plugin.name, text: lines.compactMap(\.self).joined(separator: "\n")
            )
        }
    }
}
