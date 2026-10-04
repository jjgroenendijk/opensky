// Localized labels for Scaleform menus and the HUD: the vanilla
// interface\translate_<language>.txt first, then every
// Interface/Translations/<name>_<language>.txt over it, as one `$KEY` lookup. An
// unknown key stays as written. See docs/formats/translation-strings.md.

import Foundation
import OpenSkyFormatsCore
import OSLog

nonisolated public final class LocalizedLabels: Sendable {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Strings"
    )

    /// Language segment of the translation file names; vanilla ships nine.
    public let language: String
    /// Number of translation files merged into this provider.
    public let fileCount: Int
    /// The vanilla file that was read, or nil when the install has none.
    public let vanillaPath: String?
    /// Merged `$key` -> value across every discovered file.
    private let entries: [String: String]

    public var keyCount: Int {
        entries.count
    }

    /// Merges parsed files in the given order; on a duplicate key the later file
    /// wins (provisional load-order rule, see docs/formats/translation-strings.md).
    public init(language: String, files: [TranslationFile], vanillaPath: String? = nil) {
        self.language = language
        self.vanillaPath = vanillaPath
        fileCount = files.count
        var merged: [String: String] = [:]
        for file in files {
            merged.merge(file.entries) { _, later in later }
        }
        entries = merged
    }

    /// Looks up one value by full key (leading `$` included). Nil when absent.
    public func value(forKey key: String) -> String? {
        entries[key]
    }

    /// Resolves a UI token to display text. A token beginning with `$` is looked
    /// up; an unknown key — or any token without a leading `$` — returns
    /// unchanged, the vanilla-observable behavior for an unresolved token.
    public func label(for token: String) -> String {
        guard token.first == "$" else { return token }
        return entries[token] ?? token
    }
}

nonisolated extension LocalizedLabels {
    /// Directory (VFS key) that holds the translation files.
    public static let translationsDirectory = "interface\\translations"

    /// The vanilla file for a language, such as `interface\translate_english.txt`.
    public static func vanillaPath(language: String) -> String {
        "interface\\translate_\(language.lowercased()).txt"
    }

    /// The vanilla file for `language`, or English when the install has none for
    /// it, then every mod file for `language` in sorted path order. A later file
    /// wins a duplicate key. A malformed file is logged and skipped.
    public static func load(
        vfs: any GameFileSource,
        language: String = "english"
    ) -> LocalizedLabels {
        var files: [TranslationFile] = []
        let vanilla = [vanillaPath(language: language), vanillaPath(language: "english")]
            .first { vfs.exists($0) }
        if let vanilla, let file = read(vanilla, vfs: vfs) {
            files.append(file)
        }
        let suffix = "_\(language.lowercased()).txt"
        let paths = vfs.fileNames(inDirectory: translationsDirectory)
            .filter { $0.hasSuffix(suffix) }
            .sorted()
        files += paths.compactMap { read($0, vfs: vfs) }
        return LocalizedLabels(language: language, files: files, vanillaPath: vanilla)
    }

    private static func read(_ path: String, vfs: any GameFileSource) -> TranslationFile? {
        do {
            return try TranslationFile(data: vfs.contents(forPath: path))
        } catch {
            logger.error(
                """
                Skipping unreadable translation file \(path, privacy: .public): \
                \(String(describing: error), privacy: .public)
                """
            )
            return nil
        }
    }
}
