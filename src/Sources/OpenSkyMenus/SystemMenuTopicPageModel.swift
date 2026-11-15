// The Help and Installed Content pages of the system menu: a list of topics, and
// the text of the one the player opened. See docs/engine/system-menu.md#help-and-installed-content.

import Foundation
import OpenSkyGameData
public import OpenSkyMenusInterface

/// Where the Help and Installed Content pages read their topics. The app answers
/// from the load order; without game data both lists are empty.
@MainActor
public protocol SystemMenuTopicSource: AnyObject {
    func systemMenuTopics(_ page: SystemMenuPage) -> [SystemMenuTopic]
}

nonisolated extension SystemMenuTopic {
    /// One topic per help message, titled by its `FULL`, with its `DESC` as the text.
    public static func help(_ messages: [BuiltMessage]) -> [SystemMenuTopic] {
        messages.compactMap { message in
            guard let title = message.title, !title.isEmpty else { return nil }
            return SystemMenuTopic(title: title, text: message.text)
        }
    }

    /// One topic per Creation message. The game shows each carriage return in the
    /// text as a space.
    public static func installedContent(_ messages: [BuiltMessage]) -> [SystemMenuTopic] {
        help(messages).map { topic in
            SystemMenuTopic(
                title: topic.title, text: topic.text.replacingOccurrences(of: "\r", with: " ")
            )
        }
    }
}
