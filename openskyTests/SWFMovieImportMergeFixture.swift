// Synthetic movies for the cross-movie import merge tests: a component movie
// that exports one sprite, and a chain link that both exports a sprite and
// imports the next one. Every byte comes from `SWFDisplayFixture` and
// `SWFActionFixture`; no test reads a real `.swf` (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky

enum SWFImportFixture {
    /// Character ids every fixture movie uses, so a merge that forgets to
    /// remap collides visibly.
    static let shapeId: UInt16 = 1
    static let spriteId: UInt16 = 2
    /// The placeholder id an importing movie uses for the character it borrows.
    static let placeholder: UInt16 = 60

    /// A component movie: a rectangle inside a sprite, the sprite exported
    /// under `linkage`, and a DoInitAction registering a class against it.
    /// `width` identifies which movie a merged shape came from.
    static func component(
        linkage: String,
        width: Int32,
        className: String = "Widget"
    ) throws -> SWFMovie {
        try SWFDisplayFixture.movie(tags: [
            SWFRuntimeFixture.rectangle(id: shapeId, width: width),
            SWFDisplayFixture.spriteTag(characterId: spriteId, frameCount: 1, tags: [
                SWFRuntimeFixture.place(shapeId, depth: 1, name: "art"),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.exportAssetsTag([(spriteId, linkage)]),
            SWFActionFixture.doInitActionTag(
                spriteId: spriteId,
                SWFRuntimeFixture.registerClass(name: className, linkage: linkage)
            ),
            SWFDisplayFixture.showFrameTag
        ])
    }

    /// A component that also imports one further character and places it inside
    /// its own sprite, so imports chain.
    static func link(
        linkage: String,
        width: Int32,
        importURL: String,
        importName: String
    ) throws -> SWFMovie {
        try SWFDisplayFixture.movie(tags: [
            SWFRuntimeFixture.rectangle(id: shapeId, width: width),
            SWFDisplayFixture.spriteTag(characterId: spriteId, frameCount: 1, tags: [
                SWFRuntimeFixture.place(shapeId, depth: 1, name: "art"),
                SWFRuntimeFixture.place(placeholder, depth: 2, name: "next"),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.exportAssetsTag([(spriteId, linkage)]),
            SWFDisplayFixture.importAssets2Tag(
                url: importURL, assets: [(placeholder, importName)]
            ),
            SWFDisplayFixture.showFrameTag
        ])
    }

    /// The importing movie: its own rectangle under the same id a component
    /// uses, one import, and a placement of the imported placeholder.
    /// `places` off leaves the placeholder unused, which is what a font import
    /// looks like.
    static func importer(
        url: String,
        importName: String,
        width: Int32 = 500,
        places: Bool = true,
        ownLinkage: String? = nil,
        ownInitClass: String? = nil
    ) throws -> SWFMovie {
        var tags: [SWFFixture.Tag] = [
            SWFRuntimeFixture.rectangle(id: shapeId, width: width),
            SWFDisplayFixture.importAssets2Tag(
                url: url, assets: [(placeholder, importName)]
            )
        ]
        if let ownLinkage {
            tags.append(SWFDisplayFixture.exportAssetsTag([(shapeId, ownLinkage)]))
        }
        if let ownInitClass, let ownLinkage {
            tags.append(SWFActionFixture.doInitActionTag(
                spriteId: shapeId,
                SWFRuntimeFixture.registerClass(name: ownInitClass, linkage: ownLinkage)
            ))
        }
        if places {
            tags.append(SWFRuntimeFixture.place(placeholder, depth: 1, name: "widget"))
        }
        tags.append(SWFDisplayFixture.showFrameTag)
        return try SWFDisplayFixture.movie(tags: tags)
    }

    /// The path an importing movie sits at in these tests.
    static let importerPath = "interface\\menu.swf"

    /// Merges with a resolver backed by a path -> movie table.
    static func merge(
        _ movie: SWFMovie,
        path: String = importerPath,
        sources: [String: SWFMovie]
    ) -> SWFMovie {
        SWFMovieImportMerger.merge(movie, path: path, resolve: { sources[$0] })
    }

    /// The rectangle width of the shape a merged sprite places at depth 1,
    /// which identifies the movie the sprite's art came from.
    static func artWidth(of sprite: SWFSprite, in movie: SWFMovie) -> Int32? {
        for placed in sprite.frame1 where placed.depth == 1 {
            return movie.shape(placed.characterId)?.bounds.xMax
        }
        return nil
    }

    /// The sprite a merged sprite places at depth 2 (the chained import).
    static func nextSprite(of sprite: SWFSprite, in movie: SWFMovie) -> SWFSprite? {
        for placed in sprite.frame1 where placed.depth == 2 {
            return movie.sprite(placed.characterId)
        }
        return nil
    }
}
