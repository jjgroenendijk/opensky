// Parser for the GFx Interface/fontconfig.txt file: `fontlib` movies and `map`
// aliases such as "$EverywhereFont". The grammar is observed, not specified.
// Other lines are kept in `unrecognizedLines` and reported.
// Grammar and uncertainty: docs/formats/swf-text.md.

import Foundation

nonisolated public struct SWFFontConfig: Equatable, Sendable {
    /// One `map` directive: an alias, the font name it resolves to, and any
    /// trailing style keywords (retained but not used for matching).
    public struct FontMap: Equatable, Sendable {
        public let alias: String
        public let fontName: String
        public let styles: [String]
    }

    /// Movie file names from `fontlib` directives, in file order.
    public let fontlibs: [String]
    public let maps: [FontMap]
    /// Non-empty lines that matched no recognized directive.
    public let unrecognizedLines: [String]

    /// Parses fontconfig.txt text. Never throws: unrecognized content is
    /// collected rather than failing, so a mod's extra directives cannot break
    /// font resolution.
    public static func parse(_ text: String) -> SWFFontConfig {
        var fontlibs: [String] = []
        var maps: [FontMap] = []
        var unrecognized: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                continue
            }
            let tokens = tokenize(line)
            if let movie = fontlibDirective(tokens) {
                fontlibs.append(movie)
            } else if let map = mapDirective(tokens) {
                maps.append(map)
            } else {
                unrecognized.append(line)
            }
        }
        return SWFFontConfig(fontlibs: fontlibs, maps: maps, unrecognizedLines: unrecognized)
    }

    /// Drops a `#` comment (outside quotes) to the end of the line.
    private static func stripComment(_ line: String) -> String {
        var result = ""
        var insideQuote = false
        for character in line {
            if character == "\"" {
                insideQuote.toggle()
            } else if character == "#", !insideQuote {
                break
            }
            result.append(character)
        }
        return result
    }

    /// Splits into tokens: quoted strings (unquoted), bare `=`, and bare words.
    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var insideQuote = false
        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        for character in line {
            if character == "\"" {
                if insideQuote {
                    tokens.append(current)
                    current = ""
                }
                insideQuote.toggle()
            } else if insideQuote {
                current.append(character)
            } else if character == "=" {
                flush()
                tokens.append("=")
            } else if character.isWhitespace {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()
        return tokens
    }

    /// `fontlib "movie.swf"` -> the movie name.
    private static func fontlibDirective(_ tokens: [String]) -> String? {
        guard tokens.count >= 2, tokens[0] == "fontlib" else { return nil }
        return tokens[1]
    }

    /// `map "$Alias" = "FontName" [Style ...]` -> the mapping. Trailing style
    /// keywords are optional.
    private static func mapDirective(_ tokens: [String]) -> FontMap? {
        guard tokens.count >= 4, tokens[0] == "map", tokens[2] == "=" else { return nil }
        return FontMap(
            alias: tokens[1],
            fontName: tokens[3],
            styles: Array(tokens[4...])
        )
    }
}
