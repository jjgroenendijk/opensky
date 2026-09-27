// Unit tests for the fontconfig.txt parser and the fontlib resolver. Config
// text is invented; fontlib movies are built with the synthetic SWF fixtures.

import Foundation
@testable import opensky
import Testing

struct SWFFontConfigTests {
    @Test func parsesDirectivesCommentsAndUnrecognizedLines() {
        let text = """
        # Skyrim font configuration (synthetic)

        fontlib "fonts_en.swf"
        fontlib "gfxfontlib.swf"
        map "$EverywhereFont" = "Futura Condensed" Normal
        map "$HandwrittenFont" = "MageScript"   # trailing comment
        mapdefault = "$EverywhereFont"
        """
        let config = SWFFontConfig.parse(text)
        #expect(config.fontlibs == ["fonts_en.swf", "gfxfontlib.swf"])
        #expect(config.maps.count == 2)
        #expect(config.maps[0].alias == "$EverywhereFont")
        #expect(config.maps[0].fontName == "Futura Condensed")
        #expect(config.maps[0].styles == ["Normal"])
        #expect(config.maps[1].alias == "$HandwrittenFont")
        #expect(config.maps[1].styles.isEmpty)
        // mapdefault is not in the implemented subset; retained for reporting.
        #expect(config.unrecognizedLines == ["mapdefault = \"$EverywhereFont\""])
    }

    @Test func toleratesEmptyAndCommentOnlyInput() {
        let config = SWFFontConfig.parse("# only a comment\n\n   \n")
        #expect(config.fontlibs.isEmpty)
        #expect(config.maps.isEmpty)
        #expect(config.unrecognizedLines.isEmpty)
    }

    /// A fontlib movie exposing one internally-named font and one export-named
    /// font (via ExportAssets).
    private func fontlibMovie() throws -> SWFFile {
        var named = SWFFontBodyBuilder()
        named.fontID = 3
        named.name = "Futura Condensed"
        named.codes = [65]
        named.shapes = [SWFFontBodyBuilder.triangleGlyphShape(size: 200)]

        var exported = SWFFontBodyBuilder()
        exported.fontID = 5
        exported.name = "InternalFive"
        exported.codes = [66]
        exported.shapes = [SWFFontBodyBuilder.triangleGlyphShape(size: 300)]

        var export = Data()
        export.appendUInt16(1) // one exported asset
        export.appendUInt16(5) // character id
        export.append(contentsOf: Array("ExportedFive".utf8))
        export.append(0)

        let fixture = SWFFixture(tags: [
            SWFFixture.Tag(code: 48, body: named.build()),
            SWFFixture.Tag(code: 48, body: exported.build()),
            SWFFixture.Tag(code: 56, body: export)
        ])
        return try SWFFile(data: fixture.build())
    }

    @Test func resolvesAliasThroughFontlibByInternalName() throws {
        let config = SWFFontConfig.parse("""
        fontlib "fonts_en.swf"
        map "$EverywhereFont" = "Futura Condensed" Normal
        map "$Missing" = "NoSuchFont"
        """)
        var library = SWFFontLibrary()
        try library.register(movie: "fonts_en.swf", file: fontlibMovie())

        let resolved = library.resolve(alias: "$EverywhereFont", config: config)
        #expect(resolved?.movie == "fonts_en.swf")
        #expect(resolved?.font.fontID == 3)
        #expect(library.resolve(alias: "$Missing", config: config) == nil)
        #expect(library.resolve(alias: "$Unknown", config: config) == nil)
    }

    @Test func findsFontByExportName() throws {
        var library = SWFFontLibrary()
        let added = try library.register(movie: "fonts_en.swf", file: fontlibMovie())
        #expect(added == 2)
        #expect(library.font(named: "ExportedFive")?.font.fontID == 5)
        #expect(library.font(named: "futura condensed")?.font.fontID == 3) // case-insensitive
        #expect(library.font(named: "absent") == nil)
    }
}
