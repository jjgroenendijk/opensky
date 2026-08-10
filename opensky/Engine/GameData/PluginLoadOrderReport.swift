// Display model for a resolved plugin load order: the rows and the summary the
// Load Order panel shows. It lives in the engine rather than in the panel so
// the strings a user reads are unit-tested and the AppKit file stays a shell.
//
// Positions are 1-based and decimal, not the hex master index a mod manager
// shows. The hex index is only meaningful once light plugins are placed in the
// 0xFE space, which OpenSky does not model yet (docs/formats/formid.md), and a
// hex column that is wrong for every .esl would read as authoritative.

import Foundation

nonisolated struct PluginLoadOrderReport: Equatable {
    struct Row: Equatable {
        let position: String
        let name: String
        let origin: String
        /// Empty for a plugin that loaded; otherwise why the row is listed.
        let note: String
    }

    /// Active plugins in load order, then anything listed but absent.
    let rows: [Row]
    /// One line: how many plugins loaded and where the order came from.
    let summary: String
    /// The plugins.txt path, or a stand-in when there is none.
    let pluginsTextPath: String
    /// Where that path came from, for the line under it.
    let sourceNote: String
    /// Set when the user should act: a bad override, or nothing found.
    let problem: String?

    init(resolution: PluginLoadOrder.Resolution) {
        var built: [Row] = []
        for (index, entry) in resolution.entries.enumerated() {
            built.append(Row(
                position: String(index + 1),
                name: entry.name,
                origin: entry.origin.label,
                note: ""
            ))
        }
        for absentPlugin in resolution.missing {
            built.append(Row(
                position: "—",
                name: absentPlugin.name,
                origin: absentPlugin.origin.label,
                note: "Listed active but not in Data/"
            ))
        }
        rows = built

        let count = resolution.entries.count
        let plural = count == 1 ? "plugin" : "plugins"
        let source = resolution.isVanillaFallback
            ? "no plugins.txt found — masters and Creation Club only"
            : "from plugins.txt"
        let absent = resolution.missing.isEmpty
            ? ""
            : ", \(resolution.missing.count) listed but missing"
        summary = "\(count) active \(plural) (\(source))\(absent)"

        switch resolution.location {
        case let .located(url, source):
            pluginsTextPath = url.path(percentEncoded: false)
            sourceNote = "Found in the \(PluginsTextLocator.originName(of: source))."
        case let .overrideMissing(path, source):
            pluginsTextPath = path
            sourceNote = "Configured in the \(PluginsTextLocator.originName(of: source))."
        case let .notFound(searched):
            pluginsTextPath = "Not found"
            sourceNote = searched.isEmpty
                ? "No location was searched."
                : "Searched \(searched.count) location"
                + (searched.count == 1 ? "" : "s")
                + ": " + searched.joined(separator: ", ")
        }
        problem = resolution.location.problemDescription
    }
}
