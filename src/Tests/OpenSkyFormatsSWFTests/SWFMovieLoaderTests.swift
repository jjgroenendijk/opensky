// `MovieClipLoader.loadClip` of another movie: the loading movie merges the movie its
// actions name, and the call turns the target clip into that movie's root. Synthetic
// movies only.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFMovieLoaderTests {
    /// A movie whose root places a rectangle named `art` and registers `ChildClass`.
    private static func child() throws -> SWFMovie {
        try SWFDisplayFixture.movie(tags: [
            SWFRuntimeFixture.rectangle(id: 1, width: 3000),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 1, tags: [
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.exportAssetsTag([(2, "ChildClip")]),
            SWFActionFixture.doInitActionTag(
                spriteId: 2,
                SWFRuntimeFixture.registerClass(name: "ChildClass", linkage: "ChildClip")
            ),
            SWFRuntimeFixture.place(1, depth: 1, name: "art"),
            SWFDisplayFixture.showFrameTag
        ])
    }

    /// A movie with an empty clip named `holder` and a frame action that loads `url`
    /// into it.
    private static func parent(url: String) throws -> SWFMovie {
        let load: [SWFActionFixture.Action] = [
            AS2Fixture.push([.string("loader"), .integer(0), .string("MovieClipLoader")]),
            AS2Fixture.opcode(0x40),
            AS2Fixture.opcode(0x1D)
        ] + SWFRuntimeFixture.call(
            method: "loadClip",
            on: "loader",
            arguments: [[AS2Fixture.push([.string(url)])], AS2Fixture.getVariable("holder")]
        )
        return try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.spriteTag(characterId: 5, frameCount: 1, tags: [
                SWFDisplayFixture.showFrameTag
            ]),
            SWFRuntimeFixture.place(5, depth: 3, name: "holder"),
            SWFActionFixture.doActionTag(load),
            SWFDisplayFixture.showFrameTag
        ])
    }

    private static func merged(url: String) throws -> SWFMovie {
        let child = try child()
        return try SWFMovieImportMerger.mergeLoadables(
            parent(url: url), path: "interface\\parent.swf"
        ) { path in path == "interface\\child.swf" ? child : nil }
    }

    @Test func theNamedMovieIsMergedAsASprite() throws {
        let movie = try Self.merged(url: "Child.swf")
        #expect(movie.loadedMovieNames == ["child.swf"])
        let loadable = try #require(movie.loadableMovies["child.swf"])
        #expect(movie.sprite(loadable.spriteId) != nil)
        #expect(loadable.initActions.count == 1)
        #expect(movie.importDiagnostics.mergedMovies == 1)
    }

    @Test func loadClipTurnsTheTargetIntoTheLoadedRoot() throws {
        let runtime =
            try SWFMovieRuntime(movieScene: SWFMovieScene(movie: Self.merged(url: "child.swf")))
        runtime.start()
        runtime.advance()
        let holder = try #require(runtime.root.child(named: "holder"))
        #expect(holder.characterId == runtime.movie.loadableMovies["child.swf"]?.spriteId)
        #expect(holder.child(named: "art") != nil)
        #expect(runtime.runtime.registeredClass(named: "ChildClip") != nil)
        #expect(runtime.tally.missingNames["MovieClipLoader.loadClip"] == nil)
    }

    @Test func anUnknownMovieStillFailsTheLoad() throws {
        let runtime =
            try SWFMovieRuntime(movieScene: SWFMovieScene(movie: Self.merged(url: "gone.swf")))
        runtime.start()
        #expect(runtime.movie.loadableMovies.isEmpty)
        #expect(runtime.movie.importDiagnostics.missingSourceMovies == 1)
        #expect(runtime.tally.missingNames["MovieClipLoader.loadClip"] == 1)
    }
}
