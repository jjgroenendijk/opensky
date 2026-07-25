// FrameLabel (43) and ExportAssets (56) decode (milestone 8.3.2 phase 2).
// Both are prerequisites rather than features: without frame labels
// `gotoAndStop("label")` has no target table, and without the linkage table a
// class handed to `Object.registerClass` names no character and can never be
// instantiated.
//
// Synthetic in-code fixtures only (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct SWFLinkageTests {
    // MARK: - FrameLabel

    @Test func parsesFrameLabelWithAndWithoutNamedAnchor() throws {
        let plain = try SWFFrameLabel.parse(
            tag: tag(SWFDisplayFixture.frameLabelTag("start"))
        )
        #expect(plain.name == "start")
        #expect(plain.isNamedAnchor == false)
        let anchored = try SWFFrameLabel.parse(
            tag: tag(SWFDisplayFixture.frameLabelTag("chapter", namedAnchor: true))
        )
        #expect(anchored.name == "chapter")
        #expect(anchored.isNamedAnchor)
    }

    @Test func rejectsAnotherTagCode() {
        #expect(throws: SWFDisplayListError.self) {
            try SWFFrameLabel.parse(tag: SWFTag(code: 26, body: Data([1, 2])))
        }
    }

    @Test func attachesLabelsToTheFramesTheyName() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFDisplayFixture.frameLabelTag("start"),
            SWFRuntimeFixture.place(1, depth: 1),
            SWFDisplayFixture.showFrameTag,
            SWFDisplayFixture.showFrameTag,
            SWFDisplayFixture.frameLabelTag("end"),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.timeline.frames.count == 3)
        #expect(movie.timeline.frameLabels == ["start", "end"])
        #expect(movie.timeline.frames[1].label == nil)
        #expect(movie.timeline.frameIndex(forLabel: "start") == 0)
        #expect(movie.timeline.frameIndex(forLabel: "end") == 2)
    }

    /// ActionScript path and label matching is case-insensitive below SWF 7 and
    /// authors mix casing either way, so an exact match wins and a folded match
    /// is the fallback.
    @Test func matchesLabelsCaseInsensitivelyAsAFallback() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.frameLabelTag("Ready"),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.timeline.frameIndex(forLabel: "Ready") == 0)
        #expect(movie.timeline.frameIndex(forLabel: "ready") == 0)
        #expect(movie.timeline.frameIndex(forLabel: "nothing") == nil)
    }

    @Test func labelsSurviveInsideSprites() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 2, tags: [
                SWFRuntimeFixture.place(1, depth: 1),
                SWFDisplayFixture.showFrameTag,
                SWFDisplayFixture.frameLabelTag("open"),
                SWFDisplayFixture.showFrameTag
            ])
        ])
        let sprite = try #require(movie.sprite(2))
        #expect(sprite.timeline.frameIndex(forLabel: "open") == 1)
    }

    // MARK: - ExportAssets

    @Test func parsesExportAssetsRecords() throws {
        let assets = try SWFExportedAssets.parse(
            tag: tag(SWFDisplayFixture.exportAssetsTag([(7, "PanelClip"), (9, "ButtonClip")]))
        ).assets
        #expect(assets == [
            SWFExportedAsset(characterId: 7, name: "PanelClip"),
            SWFExportedAsset(characterId: 9, name: "ButtonClip")
        ])
    }

    @Test func rejectsExportAssetsWithAnotherTagCode() {
        #expect(throws: SWFDisplayListError.self) {
            try SWFExportedAssets.parse(tag: SWFTag(code: 57, body: Data()))
        }
    }

    @Test func exposesLinkageNamesOnTheMovieInBothDirections() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFDisplayFixture.exportAssetsTag([(1, "Plate"), (2, "Panel")]),
            SWFDisplayFixture.exportAssetsTag([(3, "Extra")])
        ])
        #expect(movie.exportedNames == ["Plate": 1, "Panel": 2, "Extra": 3])
        #expect(movie.exportedIds[1] == "Plate")
        #expect(movie.exportedIds[3] == "Extra")
    }

    /// Two names for one id is legal; the reverse map keeps the
    /// alphabetically first so it stays deterministic.
    @Test func reverseLinkageMapIsDeterministicForDuplicateIds() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.exportAssetsTag([(4, "Zulu"), (4, "Alpha")])
        ])
        #expect(movie.exportedNames.count == 2)
        #expect(movie.exportedIds[4] == "Alpha")
    }

    @Test func aTruncatedExportTableFailsWithoutTakingTheMovie() throws {
        #expect(throws: (any Error).self) {
            try SWFExportedAssets.parse(tag: SWFTag(code: 56, body: Data([2, 0, 1, 0])))
        }
        // The movie decoder swallows the throw: the linkage table is lost, the
        // rest of the movie is not.
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFFixture.Tag(code: 56, body: Data([2, 0, 1, 0])),
            SWFRuntimeFixture.place(1, depth: 1),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.exportedNames.isEmpty)
        #expect(movie.frame1.count == 1)
    }

    private func tag(_ fixture: SWFFixture.Tag) -> SWFTag {
        SWFTag(code: fixture.code, body: fixture.body)
    }
}
