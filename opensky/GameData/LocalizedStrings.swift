// Resolves LStrings for one plugin: loads the plugin's per-language string
// tables (Strings/<plugin>_<language>.{strings,dlstrings,ilstrings}) through
// the VFS on first use and answers lookups. Which of the three tables an ID
// points into depends on the record field (FULL -> .strings, DESC/book text
// -> .dlstrings, dialogue -> .ilstrings), so callers pass the kind.
//
// Missing or malformed tables are logged once and yield nil lookups — a
// plugin without shipped tables must not take the engine down (mod-quirk
// rule, AGENTS.md). Format: docs/formats/strings.md.

import Foundation
import OSLog
import Synchronization

nonisolated final class LocalizedStrings: Sendable {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Strings"
    )

    private enum Slot {
        case unloaded
        case loaded(StringTable)
        case failed
    }

    private let vfs: VirtualFileSystem
    /// Plugin file name as on disk ("Skyrim.esm"); table files are named
    /// after its stem.
    let pluginName: String
    /// Language part of the table file name. Vanilla ships ten; "english"
    /// is the default until a language setting exists (see docs/todo.md).
    let language: String
    private let tables: Mutex<[StringTable.Kind: Slot]>

    init(vfs: VirtualFileSystem, pluginName: String, language: String = "english") {
        self.vfs = vfs
        self.pluginName = pluginName
        self.language = language
        tables = Mutex([.strings: .unloaded, .dlstrings: .unloaded, .ilstrings: .unloaded])
    }

    /// Resolves display text: inline strings pass through, table IDs look up
    /// the table of `kind`. Nil when the table or the ID is missing — callers
    /// choose their own placeholder.
    func resolve(_ text: LString?, kind: StringTable.Kind = .strings) -> String? {
        switch text {
        case nil:
            nil
        case let .inline(string):
            string
        case let .tableID(id):
            try? table(of: kind)?.string(id: id)
        }
    }

    private func table(of kind: StringTable.Kind) -> StringTable? {
        tables.withLock { tables in
            switch tables[kind] {
            case let .loaded(table):
                return table
            case .failed:
                return nil
            case .unloaded, nil:
                let stem = (pluginName as NSString).deletingPathExtension
                let path = "strings\\\(stem)_\(language).\(kind.fileExtension)"
                do {
                    let table = try StringTable(data: vfs.contents(forPath: path), kind: kind)
                    tables[kind] = .loaded(table)
                    return table
                } catch {
                    tables[kind] = .failed
                    Self.logger.error(
                        """
                        No usable string table \(path, privacy: .public): \
                        \(String(describing: error), privacy: .public)
                        """
                    )
                    return nil
                }
            }
        }
    }
}

extension StringTable.Kind {
    /// File extension of a table of this kind, lowercase.
    var fileExtension: String {
        switch self {
        case .strings: "strings"
        case .dlstrings: "dlstrings"
        case .ilstrings: "ilstrings"
        }
    }
}
