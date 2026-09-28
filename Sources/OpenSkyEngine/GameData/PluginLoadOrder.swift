// The engine's plugin load order: which plugins are active and in what order
// (issue #73). Everything that merges records across plugins — GMST, MOVT, the
// save fingerprint, the archive order — reads this list rather than a
// hardcoded master list.
//
// The order is built from three sources, lowest priority first:
//   1. The official masters (game + DLC), pinned in canonical order. The game
//      hardcodes these ahead of everything else and does not list them as
//      toggleable, so a plugins.txt entry for one only deduplicates.
//   2. Skyrim.ccc, the Creation Club manifest shipped in the install root.
//   3. plugins.txt, in file order. Only `*`-starred lines are active; an
//      unstarred line is a plugin the user has installed and switched off.
//
// No plugins.txt on disk -> the official masters alone, which is what a stock
// install loads anyway. Every name resolves case-insensitively against the
// real `Data/` listing, and a listed plugin that is not there is reported in
// `Resolution.missing` rather than dropped silently.
//
// Format notes and the layouts searched: docs/formats/plugins-txt.md.

import Foundation

nonisolated enum PluginLoadOrder {
    /// Why a plugin is in the order. Drives the Load Order panel's second
    /// column and nothing else — priority comes from position, not origin.
    enum Origin: Equatable {
        case implicitMaster
        case creationClub
        case pluginsText

        var label: String {
            switch self {
            case .implicitMaster: "Master"
            case .creationClub: "Creation Club"
            case .pluginsText: "plugins.txt"
            }
        }
    }

    struct Entry: Equatable {
        /// The on-disk spelling, not the spelling plugins.txt used.
        let name: String
        let url: URL
        let origin: Origin

        init(name: String, url: URL, origin: Origin = .pluginsText) {
            self.name = name
            self.url = url
            self.origin = origin
        }
    }

    /// One plugin an active-list source named that `Data/` does not hold.
    struct MissingPlugin: Equatable {
        let name: String
        let origin: Origin
    }

    struct Resolution: Equatable {
        /// Active plugins, lowest priority first.
        let entries: [Entry]
        /// Where the active list came from, or why there was none.
        let location: PluginsTextLocation
        /// Named active but absent from `Data/`, in the order named.
        let missing: [MissingPlugin]

        /// True when no plugins.txt was read and the order is the pinned
        /// masters alone.
        var isVanillaFallback: Bool {
            location.url == nil
        }
    }

    /// Resolves the load order for one install.
    ///
    /// - Parameter location: overrides the plugins.txt search. Tests pass a
    ///   fixture; production callers let `PluginsTextLocator` find it.
    static func resolve(
        root: GameDataRoot,
        location: PluginsTextLocation? = nil,
        fileManager: FileManager = .default
    ) -> Resolution {
        let location = location ?? PluginsTextLocator.locate(root: root, fileManager: fileManager)
        let onDisk = pluginsOnDisk(root: root, fileManager: fileManager)

        var listed = ArchiveLoadOrder.officialPlugins.map {
            (name: $0, origin: Origin.implicitMaster)
        }
        listed += readLines(
            root.installURL.appending(path: "Skyrim.ccc", directoryHint: .notDirectory),
            fileManager: fileManager
        )
        .compactMap(pluginName)
        .map { (name: $0, origin: Origin.creationClub) }
        if let url = location.url {
            listed += readLines(url, fileManager: fileManager)
                .compactMap(activePluginName)
                .map { (name: $0, origin: Origin.pluginsText) }
        }

        var entries: [Entry] = []
        var missing: [MissingPlugin] = []
        var seen: Set<String> = []
        for candidate in listed {
            let key = candidate.name.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            guard let actual = onDisk[key] else {
                // Only a plugins.txt entry is worth reporting. A master the
                // install lacks is an install without that DLC, and Skyrim.ccc
                // is a catalogue of everything Creation Club sells rather than
                // a list of what is installed — observed 2026-08-10, 70 of its
                // 80 entries absent from a stock install.
                if candidate.origin == .pluginsText {
                    missing.append(MissingPlugin(name: candidate.name, origin: candidate.origin))
                }
                continue
            }
            entries.append(Entry(
                name: actual,
                url: root.dataURL.appending(path: actual, directoryHint: .notDirectory),
                origin: candidate.origin
            ))
        }
        return Resolution(entries: entries, location: location, missing: missing)
    }

    /// Lowercased name -> on-disk spelling for every plugin in `Data/`.
    private static func pluginsOnDisk(
        root: GameDataRoot,
        fileManager: FileManager
    ) -> [String: String] {
        let contents = (try? fileManager.contentsOfDirectory(
            atPath: root.dataURL.path(percentEncoded: false)
        )) ?? []
        return Dictionary(
            contents.filter(Self.isPlugin).map { ($0.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private static func readLines(_ url: URL, fileManager: FileManager) -> [String] {
        guard
            fileManager.fileExists(atPath: url.path(percentEncoded: false)),
            let data = try? Data(contentsOf: url),
            let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
        else { return [] }
        return text.components(separatedBy: .newlines)
    }

    /// A plugins.txt line naming an enabled plugin. The leading `*` is the
    /// enable flag; an unstarred line is disabled and a `#` line is a comment.
    private static func activePluginName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("*") else { return nil }
        return pluginName(String(trimmed.dropFirst()))
    }

    /// A plain list line (Skyrim.ccc, or the body of a starred plugins.txt
    /// line), or nil when it is a comment, blank, or not a plugin.
    private static func pluginName(_ line: String) -> String? {
        var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        // A UTF-8 BOM survives decoding as a zero-width space on line one.
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\u{FEFF}"))
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), isPlugin(trimmed) else { return nil }
        return trimmed
    }

    private static func isPlugin(_ name: String) -> Bool {
        ["esm", "esp", "esl"].contains(URL(filePath: name).pathExtension.lowercased())
    }
}
