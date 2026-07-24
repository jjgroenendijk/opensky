// Parser for the Scaleform GFx font-configuration file the game ships at
// Interface/fontconfig.txt. It maps logical font aliases (e.g. "$EverywhereFont")
// to font names defined inside fontlib movies (e.g. fonts_en.swf), and lists
// those fontlib movies.
//
// Grammar is OBSERVED behavior, not a published spec (open GFx documentation is
// thin). The subset OpenSky implements, and its uncertainty, are documented in
// docs/formats/swf.md. Recognized directives:
//   fontlib "<movie.swf>"
//   map "$Alias" = "FontName" [Style ...]
//   # comment to end of line   (also blank lines)
// Any other non-empty line is retained verbatim in `unrecognizedLines` and
// reported, never silently dropped.

import Foundation

nonisolated struct SWFFontConfig: Equatable {
    /// One `map` directive: an alias, the font name it resolves to, and any
    /// trailing style keywords (retained but not used for matching).
    struct FontMap: Equatable {
        let alias: String
        let fontName: String
        let styles: [String]
    }

    /// Movie file names from `fontlib` directives, in file order.
    let fontlibs: [String]
    let maps: [FontMap]
    /// Non-empty lines that matched no recognized directive.
    let unrecognizedLines: [String]

    /// Parses fontconfig.txt text. Never throws: unrecognized content is
    /// collected rather than failing, so a mod's extra directives cannot break
    /// font resolution.
    static func parse(_ text: String) -> SWFFontConfig {
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
