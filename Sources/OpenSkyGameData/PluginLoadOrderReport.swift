// The rows and summary the Load Order panel shows, built here so the strings are
// unit-tested. Positions are 1-based decimal, not hex: light plugins in 0xFE are not
// modelled (docs/formats/formid.md), and a wrong hex index would look authoritative.

import Foundation

nonisolated public struct PluginLoadOrderReport: Equatable, Sendable {
    public struct Row: Equatable, Sendable {
        public let position: String
        public let name: String
        public let origin: String
        /// Empty for a plugin that loaded; otherwise why the row is listed.
        public let note: String
    }

    /// Active plugins in load order, then anything listed but absent.
    public let rows: [Row]
    /// One line: how many plugins loaded and where the order came from.
    public let summary: String
    /// The plugins.txt path, or a stand-in when there is none.
    public let pluginsTextPath: String
    /// Where that path came from, for the line under it.
    public let sourceNote: String
    /// Set when the user should act: a bad override, or nothing found.
    public let problem: String?

    public init(resolution: PluginLoadOrder.Resolution) {
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
