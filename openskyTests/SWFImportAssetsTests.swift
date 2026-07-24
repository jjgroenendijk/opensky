// ImportAssets (57) / ImportAssets2 (71) decoding and the font resolution it
// unlocks (milestone 8.2.4): a vanilla edit text names a FontID its own movie
// never defines, because the movie imports that character by name from a
// fontlib. Synthetic fixtures only.

import Foundation
@testable import opensky
import Testing

struct SWFImportAssetsTests {
    /// ImportAssets2 body: URL STRING, two reserved bytes, Count UI16, then
    /// (CharacterId UI16, Name STRING) pairs (spec v19 p. 286).
    private static func importTag(
        code: UInt16,
        url: String,
        assets: [(UInt16, String)]
    ) -> SWFTag {
        var body = Data(url.utf8)
        body.append(0)
        if code == SWFImportedAssets.importAssets2Code {
            body.append(1)
            body.append(0)
        }
        body.appendUInt16(UInt16(assets.count))
        for asset in assets {
            body.appendUInt16(asset.0)
            body.append(Data(asset.1.utf8))
            body.append(0)
        }
        return SWFTag(code: code, body: body)
    }

    @Test func importAssets2DecodesUrlAndAssets() throws {
        let imported = try SWFImportedAssets.parse(tag: Self.importTag(
            code: 71,
            url: "Interface\\fonts_en.swf",
            assets: [(3, "EverywhereFont"), (7, "EverywhereMediumFont")]
        ))
        #expect(imported.url == "Interface\\fonts_en.swf")
        #expect(imported.assets == [
            SWFImportedAsset(characterId: 3, name: "EverywhereFont"),
            SWFImportedAsset(characterId: 7, name: "EverywhereMediumFont")
        ])
    }

    /// ImportAssets (57) is the same record without the two reserved bytes.
    @Test func importAssetsDecodesWithoutReservedBytes() throws {
        let imported = try SWFImportedAssets.parse(tag: Self.importTag(
            code: 57, url: "lib.swf", assets: [(11, "FontA")]
        ))
        #expect(imported.url == "lib.swf")
        #expect(imported.assets == [SWFImportedAsset(characterId: 11, name: "FontA")])
    }

    @Test func truncatedImportThrows() {
        var body = Data("lib.swf".utf8)
        body.append(0)
        body.append(1)
        body.append(0)
        body.appendUInt16(4) // claims four assets, provides none
        #expect(throws: (any Error).self) {
            try SWFImportedAssets.parse(tag: SWFTag(code: 71, body: body))
        }
    }

    @Test func wrongTagCodeThrows() {
        #expect(throws: SWFDisplayListError.unsupportedTag(26)) {
            try SWFImportedAssets.parse(tag: SWFTag(code: 26, body: Data()))
        }
    }

    @Test func movieRecordsImportedCharacterNames() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFFixture.Tag(
                code: 71,
                body: Self.importTag(
                    code: 71, url: "Interface\\fonts_en.swf", assets: [(42, "EverywhereFont")]
                ).body
            ),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.importedNames == [42: "EverywhereFont"])
        #expect(movie.font(42) == nil)
    }

    /// The vanilla pattern end to end: an edit text points at an imported
    /// FontID, so the scene must resolve the substitution registered under the
    /// imported export name.
    @Test func editTextResolvesFontImportedByName() throws {
        var editBuilder = SWFEditTextBodyBuilder()
        editBuilder.characterId = 5
        editBuilder.bounds = SWFRect(xMin: 0, xMax: 4000, yMin: 0, yMax: 2000)
        editBuilder.flags.hasText = true
        editBuilder.flags.hasFont = true
        editBuilder.fontID = 42
        editBuilder.fontHeight = 1024
        editBuilder.initialText = "AB"
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFFixture.Tag(
                code: 71,
                body: Self.importTag(
                    code: 71, url: "Interface\\fonts_en.swf", assets: [(42, "EverywhereFont")]
                ).body
            ),
            SWFFixture.Tag(code: 37, body: editBuilder.build()),
            SWFDisplayFixture.showFrameTag
        ])
        var scene = SWFMovieScene(movie: movie)
        #expect(scene.referencedExternalFontNames == ["EverywhereFont"])
        let text = try #require(movie.editText(5))
        #expect(scene.resolvedFont(for: text) == nil)
        scene.externalFonts["EverywhereFont"] = try Self.makeFont()
        let resolved = try #require(scene.resolvedFont(for: text))
        #expect(!resolved.glyphs.isEmpty)
        #expect(SWFTextLayout.editText(text, font: resolved).runs.first?.glyphs.count == 2)
    }

    private static func makeFont() throws -> SWFFontDefinition {
        var builder = SWFFontBodyBuilder()
        builder.fontID = 1
        builder.flags.hasLayout = true
        builder.codes = [65, 66]
        builder.shapes = [
            SWFFontBodyBuilder.triangleGlyphShape(size: 700),
            SWFFontBodyBuilder.triangleGlyphShape(size: 600)
        ]
        builder.layout = SWFFontBodyBuilder.Layout(
            ascent: 800,
            descent: 200,
            leading: 0,
            advances: [600, 500],
            bounds: [
                SWFRect(xMin: 0, xMax: 700, yMin: -700, yMax: 0),
                SWFRect(xMin: 0, xMax: 600, yMin: -600, yMax: 0)
            ]
        )
        return try SWFFontParser.parse(tag: SWFTag(code: 48, body: builder.build()))
    }
}
