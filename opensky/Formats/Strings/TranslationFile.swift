// Skyrim translation-file reader for Scaleform UI menus and the HUD. Menus
// reference localized text with `$KEY` tokens that resolve against per-language
// text files at Interface/Translations/<name>_<language>.txt. Each file is
// UTF-16 little-endian with a byte-order mark, one `$key<TAB>value` pair per
// CRLF-terminated line. Keys keep their leading `$` and exact case (Scaleform
// matches keys case-sensitively).
//
// References:
//   Creation Kit wiki "Translation files" (offline at authoring; confirmed via
//     the community mirrors below).
//   SkyUI skyui-lib wiki "How to" — https://github.com/schlangster/skyui-lib/wiki/How-to
//     ("The text files have to use the UTF16 Little Endian ... with BOM
//     encoding"; "tab-separated string values"; keys prefixed with `$`).
//   ScaleformTranslationPP — https://github.com/VersuchDrei/ScaleformTranslationPP
//     ("Scaleform parses keys case-sensitively").
// Layout and decisions documented in docs/formats/translation-strings.md.

import Foundation

nonisolated enum TranslationFileError: Error, Equatable {
    /// Bytes are not decodable UTF-16 (odd byte count or an unpaired surrogate).
    case notUTF16
}

/// One parsed translation file: `$key` -> value. Decoded eagerly because these
/// files are small (a few hundred short lines). Keys keep their leading `$` and
/// exact case.
nonisolated struct TranslationFile: Equatable {
    /// `$key` (verbatim, case-sensitive) -> translated value.
    let entries: [String: String]

    var count: Int {
        entries.count
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    var keys: [String] {
        Array(entries.keys)
    }

    init(data: Data) throws {
        let text = try Self.decodeUTF16(data)
        var entries: [String: String] = [:]
        // Vanilla lines end with CRLF; tolerate lone LF and a trailing newline.
        // Split on any newline (CRLF is one grapheme, so a plain "\n" split
        // would miss it) — the CR is consumed by the split, not left on values.
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            // A line without a tab (blank lines, stray comments) carries no
            // pair; skip it rather than reject the whole file.
            guard let tab = line.firstIndex(of: "\t") else { continue }
            let key = String(line[..<tab])
            guard !key.isEmpty else { continue }
            let value = String(line[line.index(after: tab)...])
            // Duplicate key within a file: the later line wins (override).
            entries[key] = value
        }
        self.entries = entries
    }

    /// Looks up one value by full key (leading `$` included). Nil when absent.
    func value(forKey key: String) -> String? {
        entries[key]
    }

    /// Decodes the file body as UTF-16. A leading byte-order mark selects the
    /// byte order (FF FE little-endian, FE FF big-endian); without a mark the
    /// format specifies little-endian, so assume it.
    private static func decodeUTF16(_ data: Data) throws -> String {
        var bytes = data
        let encoding: String.Encoding
        let start = bytes.startIndex
        if bytes.count >= 2, bytes[start] == 0xFF, bytes[start + 1] == 0xFE {
            bytes = bytes.dropFirst(2)
            encoding = .utf16LittleEndian
        } else if bytes.count >= 2, bytes[start] == 0xFE, bytes[start + 1] == 0xFF {
            bytes = bytes.dropFirst(2)
            encoding = .utf16BigEndian
        } else {
            encoding = .utf16LittleEndian
        }
        guard let text = String(data: bytes, encoding: encoding) else {
            throw TranslationFileError.notUTF16
        }
        return text
    }
}
