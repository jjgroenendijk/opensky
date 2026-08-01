// Cross-movie character import (ImportAssets 57 / ImportAssets2 71): the
// uniform-offset merge that gives an importing movie the characters, linkage
// names, and DoInitAction registrations of the movies it borrows from.
// Synthetic fixtures only — the resolver seam stands in for the VFS, so none of
// this touches a real install.

import Foundation
@testable import opensky
import Testing

struct SWFMovieImportMergeTests {
    // MARK: - Path resolution

    @Test func importURLResolvesAgainstTheImportersDirectory() {
        #expect(
            SWFMovieImportMerger.resolvedPath(
                for: "Inventory components/ItemCard.swf",
                relativeTo: "interface\\inventorymenu.swf"
            ) == "interface\\inventory components\\itemcard.swf"
        )
        #expect(
            SWFMovieImportMerger.resolvedPath(
                for: "gfxfontlib.swf", relativeTo: "Interface\\InventoryMenu.swf"
            ) == "interface\\gfxfontlib.swf"
        )
        #expect(
            SWFMovieImportMerger.resolvedPath(
                for: "../shared/lib.swf", relativeTo: "interface\\sub\\menu.swf"
            ) == "interface\\shared\\lib.swf"
        )
        #expect(
            SWFMovieImportMerger.resolvedPath(for: "", relativeTo: "menu.swf") == nil
        )
    }

    // MARK: - The basic merge

    @Test func importedSpriteIsMergedRemappedAndBound() throws {
        let source = try SWFImportFixture.component(linkage: "Widget", width: 3000)
        let merged = try SWFImportFixture.merge(
            SWFImportFixture.importer(url: "lib.swf", importName: "Widget"),
            sources: ["interface\\lib.swf": source]
        )
        let sprite = try #require(merged.sprite(SWFImportFixture.placeholder))
        // The placeholder now holds the source's sprite, and that sprite's own
        // placement points at the source's shape under its remapped id.
        #expect(SWFImportFixture.artWidth(of: sprite, in: merged) == 3000)
        #expect(sprite.characterId != SWFImportFixture.spriteId)
        #expect(merged.importDiagnostics.mergedMovies == 1)
        #expect(merged.importDiagnostics.boundPlaceholders == 1)
        #expect(merged.importDiagnostics.unresolvedPlaceholders == 0)
        #expect(merged.importDiagnostics.mergedPaths == ["interface\\lib.swf"])
    }

    /// The importing movie and the source both define characters 1 and 2. The
    /// merge must not let the source overwrite either.
    @Test func collidingIdsSurviveTheMerge() throws {
        let source = try SWFImportFixture.component(linkage: "Widget", width: 3000)
        let merged = try SWFImportFixture.merge(
            SWFImportFixture.importer(url: "lib.swf", importName: "Widget", width: 500),
            sources: ["interface\\lib.swf": source]
        )
        #expect(merged.shape(SWFImportFixture.shapeId)?.bounds.xMax == 500)
        #expect(merged.sprite(SWFImportFixture.spriteId) == nil)
        // Both rectangles are present, under different ids.
        let widths = merged.characters.keys.sorted().compactMap { merged.shape($0)?.bounds.xMax }
        #expect(widths.sorted() == [500, 3000])
    }

    /// A linkage name both movies claim resolves in the importing movie's
    /// favour: its own bytecode registered classes against its own definition.
    @Test func linkageNameCollisionKeepsTheImportersDefinition() throws {
        let source = try SWFImportFixture.component(linkage: "Widget", width: 3000)
        let importer = try SWFImportFixture.importer(
            url: "lib.swf", importName: "Widget", ownLinkage: "Widget"
        )
        let merged = SWFImportFixture.merge(importer, sources: ["interface\\lib.swf": source])
        #expect(merged.exportedNames["Widget"] == SWFImportFixture.shapeId)
        #expect(merged.shape(SWFImportFixture.shapeId)?.bounds.xMax == 500)
        // The placeholder still resolves to the source's sprite, and takes the
        // imported name so a registered class can find it by character id.
        #expect(merged.sprite(SWFImportFixture.placeholder) != nil)
        #expect(merged.exportedIds[SWFImportFixture.placeholder] == "Widget")
    }

    /// Imported DoInitAction blocks run before the importing movie's own, so a
    /// borrowed class is registered before anything instantiates it.
    @Test func importedInitActionsRunFirst() throws {
        let source = try SWFImportFixture.component(linkage: "Widget", width: 3000)
        let importer = try SWFImportFixture.importer(
            url: "lib.swf", importName: "Widget",
            ownLinkage: "Panel", ownInitClass: "PanelClass"
        )
        #expect(importer.initActions.count == 1)
        let merged = SWFImportFixture.merge(importer, sources: ["interface\\lib.swf": source])
        #expect(merged.initActions.count == 2)
        // The source's block comes first, with its sprite id remapped.
        #expect(merged.initActions[0].spriteId != SWFImportFixture.spriteId)
        #expect(merged.initActions[1].spriteId == SWFImportFixture.shapeId)
    }

    // MARK: - Degradation

    @Test func unresolvableSourceIsADiagnosticNotAThrow() throws {
        let importer = try SWFImportFixture.importer(url: "lib.swf", importName: "Widget")
        let merged = SWFImportFixture.merge(importer, sources: [:])
        #expect(merged.importDiagnostics.missingSourceMovies == 1)
        #expect(merged.importDiagnostics.mergedMovies == 0)
        #expect(merged.characters.count == importer.characters.count)
        #expect(merged.sprite(SWFImportFixture.placeholder) == nil)
    }

    @Test func nameTheSourceDoesNotExportLeavesThePlaceholderUnresolved() throws {
        let source = try SWFImportFixture.component(linkage: "Other", width: 3000)
        let merged = try SWFImportFixture.merge(
            SWFImportFixture.importer(url: "lib.swf", importName: "Widget"),
            sources: ["interface\\lib.swf": source]
        )
        #expect(merged.importDiagnostics.unresolvedPlaceholders == 1)
        #expect(merged.importDiagnostics.boundPlaceholders == 0)
        #expect(merged.sprite(SWFImportFixture.placeholder) == nil)
        // The source still merged, so its own characters are addressable.
        #expect(merged.exportedNames["Other"] != nil)
    }

    /// An import nothing places and nothing re-exports is skipped without the
    /// source ever being loaded — the font-import case.
    @Test func fontShapedImportIsSkippedWithoutLoadingTheSource() throws {
        var requests: [String] = []
        let importer = try SWFImportFixture.importer(
            url: "gfxfontlib.swf", importName: "$EverywhereMediumFont", places: false
        )
        let merged = SWFMovieImportMerger.merge(
            importer,
            path: SWFImportFixture.importerPath,
            resolve: { path in
                requests.append(path)
                return nil
            }
        )
        #expect(requests.isEmpty)
        #expect(merged.importDiagnostics.skippedImports == 1)
        #expect(merged.importDiagnostics.mergedMovies == 0)
    }

    // MARK: - Recursion

    @Test func importsResolveRecursively() throws {
        let outer = try SWFImportFixture.link(
            linkage: "Outer", width: 700, importURL: "inner.swf", importName: "Inner"
        )
        let inner = try SWFImportFixture.component(linkage: "Inner", width: 900)
        let merged = try SWFImportFixture.merge(
            SWFImportFixture.importer(url: "lib.swf", importName: "Outer"),
            sources: ["interface\\lib.swf": outer, "interface\\inner.swf": inner]
        )
        let sprite = try #require(merged.sprite(SWFImportFixture.placeholder))
        #expect(SWFImportFixture.artWidth(of: sprite, in: merged) == 700)
        let nested = try #require(SWFImportFixture.nextSprite(of: sprite, in: merged))
        #expect(SWFImportFixture.artWidth(of: nested, in: merged) == 900)
        #expect(merged.importDiagnostics.mergedMovies == 2)
        #expect(merged.importDiagnostics.boundPlaceholders == 2)
    }

    /// Two movies importing each other terminate, and the one that can be
    /// merged still is.
    @Test func cyclicImportsTerminate() throws {
        let first = try SWFImportFixture.link(
            linkage: "First", width: 700, importURL: "second.swf", importName: "Second"
        )
        let second = try SWFImportFixture.link(
            linkage: "Second", width: 900, importURL: "first.swf", importName: "First"
        )
        let merged = SWFImportFixture.merge(
            first,
            path: "interface\\first.swf",
            sources: ["interface\\second.swf": second, "interface\\first.swf": first]
        )
        #expect(merged.importDiagnostics.mergedMovies == 1)
        #expect(merged.importDiagnostics.cyclicImports == 1)
        #expect(merged.sprite(SWFImportFixture.placeholder) != nil)
    }

    /// An unbounded chain stops at `maximumDepth` with a diagnostic.
    @Test func depthBoundStopsAnEndlessChain() throws {
        let merged = try SWFMovieImportMerger.merge(
            SWFImportFixture.importer(url: "lib1.swf", importName: "Level1"),
            path: SWFImportFixture.importerPath,
            resolve: { path in try? Self.chainMovie(atPath: path) }
        )
        #expect(merged.importDiagnostics.mergedMovies == SWFMovieImportMerger.maximumDepth)
        #expect(merged.importDiagnostics.depthLimitHits == 1)
        #expect(merged.sprite(SWFImportFixture.placeholder) != nil)
    }

    /// `interface\libN.swf` -> a link exporting `LevelN` and importing
    /// `LevelN+1`, so the resolver can serve an endless chain.
    private static func chainMovie(atPath path: String) throws -> SWFMovie? {
        let digits = path.drop { !$0.isNumber }.prefix { $0.isNumber }
        guard let level = Int(digits) else {
            return nil
        }
        return try SWFImportFixture.link(
            linkage: "Level\(level)",
            width: Int32(100 * level),
            importURL: "lib\(level + 1).swf",
            importName: "Level\(level + 1)"
        )
    }
}
