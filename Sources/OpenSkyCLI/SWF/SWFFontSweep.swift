// Font and static-text portion of `swf sweep` (milestone 8.2.3 gate): decodes
// every DefineFont2/3, DefineText/2, and DefineEditText tag across the vanilla
// Interface movies, exercises the glyph -> CGPath conversion that feeds the
// atlas, and reports fontconfig alias resolution against the fontlib movies.
// Any vanilla font/text decode failure fails the sweep.

import Foundation

/// Accumulates font + text decode results across an `swf sweep` run.
struct SWFFontTextTally {
    /// Pixel size used to exercise glyph -> CGPath conversion (not rendered).
    private static let probePixelSize = 64

    var fontCount = 0
    var fontsWithLayout = 0
    var glyphTotal = 0
    var glyphsWithCode = 0
    var glyphPathsBuilt = 0
    var kerningPairs = 0
    var defineTextCount = 0
    var defineText2Count = 0
    var editTextCount = 0
    var editTextWithText = 0
    var htmlEditTextCount = 0
    var textRecordGlyphs = 0
    var failures: [(String, String)] = []

    mutating func record(_ file: SWFFile, path: String) {
        for tag in file.tags {
            switch tag.code {
            case 48, 75: recordFont(tag, path: path)
            case 11, 33: recordText(tag, path: path)
            case SWFEditText.tagCode: recordEditText(tag, path: path)
            default: break
            }
        }
    }

    private mutating func recordFont(_ tag: SWFTag, path: String) {
        do {
            let font = try SWFFontParser.parse(tag: tag)
            fontCount += 1
            glyphTotal += font.glyphs.count
            glyphsWithCode += font.glyphs.count { $0.code != 0 }
            if let layout = font.layout {
                fontsWithLayout += 1
                kerningPairs += layout.kerning.count
            }
            glyphPathsBuilt += font.glyphs.count { glyph in
                SWFGlyphPath.makePath(
                    segments: glyph.segments,
                    unitsPerEM: font.unitsPerEM,
                    emPixelSize: Self.probePixelSize
                ) != nil
            }
        } catch {
            failures.append(("\(path) font tag \(tag.code)", String(describing: error)))
        }
    }

    private mutating func recordText(_ tag: SWFTag, path: String) {
        do {
            let text = try SWFTextDefinition.parse(tag: tag)
            if tag.code == 33 {
                defineText2Count += 1
            } else {
                defineTextCount += 1
            }
            textRecordGlyphs += text.records.reduce(0) { $0 + $1.glyphs.count }
        } catch {
            failures.append(("\(path) text tag \(tag.code)", String(describing: error)))
        }
    }

    private mutating func recordEditText(_ tag: SWFTag, path: String) {
        do {
            let edit = try SWFEditText.parse(tag: tag)
            editTextCount += 1
            if edit.initialText != nil {
                editTextWithText += 1
            }
            if edit.flags.html {
                htmlEditTextCount += 1
            }
        } catch {
            failures.append(("\(path) edit text tag \(tag.code)", String(describing: error)))
        }
    }

    func printReport() {
        print(
            "[INFO] swf sweep fonts: \(fontCount) decoded "
                + "(\(fontsWithLayout) with layout), \(glyphTotal) glyphs, "
                + "\(glyphsWithCode) code-mapped, \(glyphPathsBuilt) paths built, "
                + "\(kerningPairs) kerning pairs, \(fontFailureCount) failed"
        )
        print(
            "[INFO] swf sweep text: DefineText \(defineTextCount), "
                + "DefineText2 \(defineText2Count), \(textRecordGlyphs) placed glyphs, "
                + "DefineEditText \(editTextCount) (\(editTextWithText) with text, "
                + "\(htmlEditTextCount) HTML), \(textFailureCount) failed"
        )
    }

    /// Font-only failures, split for the two report lines.
    private var fontFailureCount: Int {
        failures.count { $0.0.contains("font tag") }
    }

    private var textFailureCount: Int {
        failures.count - fontFailureCount
    }
}

/// Reports fontconfig alias resolution: parses `interface\fontconfig.txt`, loads
/// its fontlib movies, and tallies how many `map` aliases resolve to a font.
enum SWFFontConfigReport {
    private static let fontconfigPath = "interface\\fontconfig.txt"

    static func run(vfs: VirtualFileSystem) {
        guard let data = try? vfs.contents(forPath: fontconfigPath) else {
            print("[INFO] swf sweep fontconfig: \(fontconfigPath) not found (no report)")
            return
        }
        let config = SWFFontConfig.parse(decodeText(data))
        var library = SWFFontLibrary()
        var missingLibs: [String] = []
        for movie in config.fontlibs {
            // fontlib names are already install-relative paths (e.g.
            // "Interface\fonts_en.swf"); the VFS normalizes case + separators.
            if let file = try? SWFFile(data: vfs.contents(forPath: movie)) {
                library.register(movie: movie, file: file)
            } else {
                missingLibs.append(movie)
            }
        }
        var resolved = 0
        var unresolved: [String] = []
        for map in config.maps where !map.alias.isEmpty {
            if library.resolve(alias: map.alias, config: config) != nil {
                resolved += 1
            } else {
                unresolved.append(map.alias)
            }
        }
        printSummary(
            config: config, resolved: resolved,
            unresolved: unresolved, missingLibs: missingLibs
        )
    }

    private static func printSummary(
        config: SWFFontConfig,
        resolved: Int,
        unresolved: [String],
        missingLibs: [String]
    ) {
        let libs = config.fontlibs.joined(separator: ", ")
        print(
            "[INFO] swf sweep fontconfig: \(config.fontlibs.count) fontlibs [\(libs)], "
                + "\(config.maps.count) aliases, \(resolved) resolved, "
                + "\(unresolved.count) unresolved"
        )
        if !missingLibs.isEmpty {
            print("[INFO]   fontlibs not found: \(missingLibs.joined(separator: ", "))")
        }
        for alias in unresolved.prefix(20) {
            print("[INFO]   unresolved alias: \(alias)")
        }
        for line in config.unrecognizedLines.prefix(10) {
            print("[INFO]   unrecognized directive: \(line)")
        }
    }

    /// fontconfig.txt is plain text; UTF-8 with a CP1252 fallback so a stray
    /// byte never drops the whole file.
    private static func decodeText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252) ?? ""
    }
}
