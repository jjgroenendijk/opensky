// The Help and Installed Content pages of the system menu: a list of topics, and
// the text of the one the player opened. See docs/engine/system-menu.md#help-and-installed-content.

import Foundation
public import OpenSkyGameData
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
