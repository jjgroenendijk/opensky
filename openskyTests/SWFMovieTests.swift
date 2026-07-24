// Movie-model and scene-flattening tests (milestone 8.2.4): dictionary
// building, place/move/replace/remove semantics up to the first ShowFrame,
// DefineSprite nesting, clip-depth command generation with the counting
// stencil scheme, and the recorded-feature tallies. Synthetic fixtures only.

import Foundation
@testable import opensky
import Testing

struct SWFMovieTests {
    private static let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)
    private static let blue = SWFColor(red: 0, green: 0, blue: 255, alpha: 255)

    @Test func frame1CollectsPlacementsByDepth() throws {
        var placeTwo = SWFDisplayFixture.Place2()
        placeTwo.depth = 2
        placeTwo.characterId = 20
        var placeOne = SWFDisplayFixture.Place2()
        placeOne.depth = 1
        placeOne.characterId = 10
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: Self.red
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 20, width: 500, height: 500, color: Self.blue
            ),
            SWFDisplayFixture.placeObject2Tag(placeTwo),
            SWFDisplayFixture.placeObject2Tag(placeOne),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.frame1.map(\.depth) == [1, 2])
        #expect(movie.frame1.map(\.characterId) == [10, 20])
        #expect(movie.characters.count == 2)
        #expect(movie.tally.placeObject2 == 2)
        #expect(movie.tally.showFrames == 1)
    }

    @Test func moveModifiesExistingPlacementKeepingCharacter() throws {
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 10
        place.matrix = SWFDisplayFixture.MatrixSpec(translateX: 100, translateY: 100)
        var move = SWFDisplayFixture.Place2()
        move.depth = 1
        move.move = true
        move.matrix = SWFDisplayFixture.MatrixSpec(translateX: 700, translateY: 100)
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: Self.red
            ),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.placeObject2Tag(move),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.frame1.count == 1)
        #expect(movie.frame1.first?.characterId == 10)
        #expect(movie.frame1.first?.matrix.translateX == 700)
        #expect(movie.tally.moves == 1)
    }

    @Test func replaceSwapsCharacterKeepingUnspecifiedState() throws {
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 10
        place.matrix = SWFDisplayFixture.MatrixSpec(translateX: 300, translateY: 400)
        var replace = SWFDisplayFixture.Place2()
        replace.depth = 1
        replace.move = true
        replace.characterId = 20
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: Self.red
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 20, width: 500, height: 500, color: Self.blue
            ),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.placeObject2Tag(replace),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.frame1.first?.characterId == 20)
        // Observed Flash/GFx behavior: the replace keeps the previous matrix.
        #expect(movie.frame1.first?.matrix.translateX == 300)
    }

    @Test func removalsEmptyTheDepth() throws {
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 10
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: Self.red
            ),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.removeObject2Tag(depth: 1),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.frame1.isEmpty)
        #expect(movie.tally.removals == 1)
    }

    @Test func timelineStopsAtFirstShowFrame() throws {
        var first = SWFDisplayFixture.Place2()
        first.depth = 1
        first.characterId = 10
        var second = SWFDisplayFixture.Place2()
        second.depth = 2
        second.characterId = 10
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: Self.red
            ),
            SWFDisplayFixture.placeObject2Tag(first),
            SWFDisplayFixture.showFrameTag,
            SWFDisplayFixture.placeObject2Tag(second),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.frame1.count == 1)
        #expect(movie.tally.showFrames == 1)
    }

    @Test func modifyOnEmptyDepthCountsAsDangling() throws {
        var move = SWFDisplayFixture.Place2()
        move.depth = 4
        move.move = true
        move.matrix = SWFDisplayFixture.MatrixSpec(translateX: 1, translateY: 1)
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.placeObject2Tag(move),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.frame1.isEmpty)
        #expect(movie.tally.danglingPlacements == 1)
    }

    @Test func backgroundColorIsCaptured() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.backgroundColorTag(Self.blue),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.backgroundColor == Self.blue)
    }

    @Test func spriteDecodesItsOwnFrame1() throws {
        var inner = SWFDisplayFixture.Place2()
        inner.depth = 1
        inner.characterId = 10
        inner.matrix = SWFDisplayFixture.MatrixSpec(translateX: 50, translateY: 60)
        var outer = SWFDisplayFixture.Place2()
        outer.depth = 3
        outer.characterId = 30
        outer.matrix = SWFDisplayFixture.MatrixSpec(translateX: 1000, translateY: 0)
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: Self.red
            ),
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 4, tags: [
                SWFDisplayFixture.placeObject2Tag(inner),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(outer),
            SWFDisplayFixture.showFrameTag
        ])
        let sprite = try #require(movie.sprite(30))
        #expect(sprite.frameCount == 4)
        #expect(sprite.frame1.count == 1)
        #expect(sprite.frame1.first?.matrix.translateX == 50)
        #expect(movie.tally.sprites == 1)
    }

    @Test func placeObject3FeatureTalliesAreRecorded() throws {
        var place3 = SWFDisplayFixture.Place3()
        place3.place.depth = 1
        place3.place.characterId = 10
        place3.blendMode = 5
        place3.blurFilterCount = 3
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 10, width: 1000, height: 1000, color: Self.red
            ),
            SWFDisplayFixture.placeObject3Tag(place3),
            SWFDisplayFixture.showFrameTag
        ])
        #expect(movie.tally.placeObject3 == 1)
        #expect(movie.tally.blendModes == 1)
        #expect(movie.tally.filters == 3)
    }
}

struct SWFSceneTests {
    private static let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)

    private static func shapeTag(_ id: UInt16) -> SWFFixture.Tag {
        SWFDisplayFixture.rectangleShapeTag(
            characterId: id, width: 1000, height: 1000, color: red
        )
    }

    @Test func drawsFollowDepthOrderWithConcatenatedTransforms() throws {
        var inner = SWFDisplayFixture.Place2()
        inner.depth = 1
        inner.characterId = 10
        inner.matrix = SWFDisplayFixture.MatrixSpec(translateX: 100, translateY: 0)
        var outer = SWFDisplayFixture.Place2()
        outer.depth = 1
        outer.characterId = 30
        outer.matrix = SWFDisplayFixture.MatrixSpec(
            scaleX: 2, scaleY: 2, translateX: 1000, translateY: 500
        )
        let movie = try SWFDisplayFixture.movie(tags: [
            Self.shapeTag(10),
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.placeObject2Tag(inner),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(outer),
            SWFDisplayFixture.showFrameTag
        ])
        let scene = SWFScene.build(movie: movie)
        #expect(scene.commands.count == 1)
        guard case let .draw(item, clipCount) = scene.commands[0] else {
            Issue.record("expected a draw command")
            return
        }
        #expect(clipCount == 0)
        // movie transform: scale 2 + translate (1000, 500); sprite child
        // translate (100, 0) -> origin maps to 1000 + 2*100 = 1200.
        let origin = item.transform.apply(SIMD2(0, 0))
        #expect(origin.x == 1200)
        #expect(origin.y == 500)
    }

    @Test func clipLayerBracketsClippedDepthsOnly() throws {
        var mask = SWFDisplayFixture.Place2()
        mask.depth = 1
        mask.characterId = 10
        mask.clipDepth = 2
        var clipped = SWFDisplayFixture.Place2()
        clipped.depth = 2
        clipped.characterId = 11
        var unclipped = SWFDisplayFixture.Place2()
        unclipped.depth = 3
        unclipped.characterId = 12
        let movie = try SWFDisplayFixture.movie(tags: [
            Self.shapeTag(10), Self.shapeTag(11), Self.shapeTag(12),
            SWFDisplayFixture.placeObject2Tag(mask),
            SWFDisplayFixture.placeObject2Tag(clipped),
            SWFDisplayFixture.placeObject2Tag(unclipped),
            SWFDisplayFixture.showFrameTag
        ])
        let scene = SWFScene.build(movie: movie)
        #expect(scene.commands.count == 4)
        guard
            case let .beginClip(masks) = scene.commands[0],
            case let .draw(_, insideCount) = scene.commands[1],
            case let .endClip(endMasks) = scene.commands[2],
            case let .draw(_, outsideCount) = scene.commands[3]
        else {
            Issue.record("unexpected command order: \(scene.commands)")
            return
        }
        #expect(masks.count == 1)
        #expect(endMasks == masks)
        #expect(insideCount == 1)
        #expect(outsideCount == 0)
    }

    @Test func interleavedClipRangesCountActiveMasks() throws {
        var maskA = SWFDisplayFixture.Place2()
        maskA.depth = 1
        maskA.characterId = 10
        maskA.clipDepth = 6
        var maskB = SWFDisplayFixture.Place2()
        maskB.depth = 2
        maskB.characterId = 11
        maskB.clipDepth = 4
        var inBoth = SWFDisplayFixture.Place2()
        inBoth.depth = 3
        inBoth.characterId = 12
        var inAOnly = SWFDisplayFixture.Place2()
        inAOnly.depth = 5
        inAOnly.characterId = 12
        let movie = try SWFDisplayFixture.movie(tags: [
            Self.shapeTag(10), Self.shapeTag(11), Self.shapeTag(12),
            SWFDisplayFixture.placeObject2Tag(maskA),
            SWFDisplayFixture.placeObject2Tag(maskB),
            SWFDisplayFixture.placeObject2Tag(inBoth),
            SWFDisplayFixture.placeObject2Tag(inAOnly),
            SWFDisplayFixture.showFrameTag
        ])
        let scene = SWFScene.build(movie: movie)
        let clipCounts = scene.commands.compactMap { command -> Int? in
            if case let .draw(_, clipCount) = command {
                return clipCount
            }
            return nil
        }
        #expect(clipCounts == [2, 1])
    }

    @Test func spriteMaskContributesItsShapes() throws {
        var inner = SWFDisplayFixture.Place2()
        inner.depth = 1
        inner.characterId = 10
        var mask = SWFDisplayFixture.Place2()
        mask.depth = 1
        mask.characterId = 30
        mask.clipDepth = 3
        var content = SWFDisplayFixture.Place2()
        content.depth = 2
        content.characterId = 11
        let movie = try SWFDisplayFixture.movie(tags: [
            Self.shapeTag(10), Self.shapeTag(11),
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.placeObject2Tag(inner),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(mask),
            SWFDisplayFixture.placeObject2Tag(content),
            SWFDisplayFixture.showFrameTag
        ])
        let scene = SWFScene.build(movie: movie)
        guard case let .beginClip(masks) = scene.commands.first else {
            Issue.record("expected beginClip first: \(scene.commands)")
            return
        }
        #expect(masks.count == 1)
        #expect(masks.first?.content == .shape(10))
    }

    @Test func danglingCharacterIdIsSkipped() throws {
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 99
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ])
        let scene = SWFScene.build(movie: movie)
        #expect(scene.commands.isEmpty)
        #expect(scene.skippedPlacements == 1)
    }

    @Test func colorTransformsConcatenateThroughSprites() throws {
        var inner = SWFDisplayFixture.Place2()
        inner.depth = 1
        inner.characterId = 10
        inner.cxform = SWFDisplayFixture.CxformSpec(multiplyTerms: [128, 256, 256, 256])
        var outer = SWFDisplayFixture.Place2()
        outer.depth = 1
        outer.characterId = 30
        outer.cxform = SWFDisplayFixture.CxformSpec(multiplyTerms: [128, 128, 256, 256])
        let movie = try SWFDisplayFixture.movie(tags: [
            Self.shapeTag(10),
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.placeObject2Tag(inner),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(outer),
            SWFDisplayFixture.showFrameTag
        ])
        let scene = SWFScene.build(movie: movie)
        guard case let .draw(item, _) = scene.commands.first else {
            Issue.record("expected draw: \(scene.commands)")
            return
        }
        #expect(item.colorTransform.multiply.x == 0.25)
        #expect(item.colorTransform.multiply.y == 0.5)
        #expect(item.colorTransform.multiply.z == 1)
    }
}
