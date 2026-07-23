// Localized-label provider for Scaleform UI menus and the HUD (M8.1.3). Menus
// carry `$KEY` tokens; this merges every Interface/Translations/<name>_<language>.txt
// the VFS resolves into one lookup and answers a token with its display text.
// An unknown key returns the token unchanged, matching Scaleform leaving an
// unresolved `$KEY` visible on screen. Localization backbone for the HUD (M8.2)
// and vanilla SWF menus (issue #99).
//
// Distinct from LocalizedStrings, which resolves plugin lstring IDs against the
// per-plugin .strings/.dlstrings/.ilstrings tables. This provider handles the
// UI translation-token files. Format and decisions: docs/formats/translation-strings.md.

import Foundation
import OSLog

nonisolated final class LocalizedLabels: Sendable {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Strings"
    )

    /// Language segment of the translation file names. "english" is the default
    /// until a language setting exists (see docs/todo.md); vanilla ships ten.
    let language: String
    /// Number of translation files merged into this provider.
    let fileCount: Int
    /// Merged `$key` -> value across every discovered file.
    private let entries: [String: String]

    var keyCount: Int {
        entries.count
    }

    /// Merges parsed files in the given order; on a duplicate key the later file
    /// wins (provisional load-order rule, see docs/formats/translation-strings.md).
    init(language: String, files: [TranslationFile]) {
        self.language = language
        fileCount = files.count
        var merged: [String: String] = [:]
        for file in files {
            merged.merge(file.entries) { _, later in later }
        }
        entries = merged
    }

    /// Looks up one value by full key (leading `$` included). Nil when absent.
    func value(forKey key: String) -> String? {
        entries[key]
    }

    /// Resolves a UI token to display text. A token beginning with `$` is looked
    /// up; an unknown key — or any token without a leading `$` — returns
    /// unchanged, the vanilla-observable behavior for an unresolved token.
    func label(for token: String) -> String {
        guard token.first == "$" else { return token }
        return entries[token] ?? token
    }
}

extension LocalizedLabels {
    /// Directory (VFS key) that holds the translation files.
    static let translationsDirectory = "interface\\translations"

    /// Discovers and merges every `<name>_<language>.txt` under
    /// Interface/Translations that the VFS resolves (loose files and archives).
    /// A malformed file is logged and skipped so one bad file cannot take the
    /// provider down (mod-quirk rule, AGENTS.md).
    static func load(vfs: VirtualFileSystem, language: String = "english") -> LocalizedLabels {
        let suffix = "_\(language.lowercased()).txt"
        let paths = vfs.fileNames(inDirectory: translationsDirectory)
            .filter { $0.hasSuffix(suffix) }
        var files: [TranslationFile] = []
        files.reserveCapacity(paths.count)
        for path in paths {
            do {
                try files.append(TranslationFile(data: vfs.contents(forPath: path)))
            } catch {
                logger.error(
                    """
                    Skipping unreadable translation file \(path, privacy: .public): \
                    \(String(describing: error), privacy: .public)
                    """
                )
            }
        }
        return LocalizedLabels(language: language, files: files)
    }
}
