// Resolves one plugin's lstrings from Strings/<plugin>_<language>.{strings,dlstrings,
// ilstrings}, loaded lazily. The field picks the table (FULL -> .strings, journal and
// books -> .dlstrings, dialogue -> .ilstrings), so callers pass the kind. A missing or
// bad table is logged once and gives nil. See docs/formats/strings.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OSLog
import Synchronization

nonisolated public final class LocalizedStrings: Sendable {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Strings"
    )

    private enum Slot {
        case unloaded
        case loaded(StringTable)
        case failed
    }

    private let vfs: any GameFileSource
    /// Plugin file name as on disk ("Skyrim.esm"); table files are named
    /// after its stem.
    public let pluginName: String
    /// Normalized language part of the table file name. The app resolves this
    /// from Skyrim.ini or its persistent Settings override.
    public let language: String
    private let tables: Mutex<[StringTable.Kind: Slot]>

    public init(vfs: any GameFileSource, pluginName: String, language: String = "english") {
        self.vfs = vfs
        self.pluginName = pluginName
        self.language = language
        tables = Mutex([.strings: .unloaded, .dlstrings: .unloaded, .ilstrings: .unloaded])
    }

    /// Resolves display text: inline strings pass through, table IDs look up
    /// the table of `kind`. Nil when the table or the ID is missing — callers
    /// choose their own placeholder.
    public func resolve(_ text: LString?, kind: StringTable.Kind = .strings) -> String? {
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

nonisolated extension StringTable.Kind {
    /// File extension of a table of this kind, lowercase.
    public var fileExtension: String {
        switch self {
        case .strings: "strings"
        case .dlstrings: "dlstrings"
        case .ilstrings: "ilstrings"
        }
    }
}
