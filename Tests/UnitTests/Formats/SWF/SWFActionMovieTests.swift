// Reachability of action streams from the movie model (milestone 8.3.1):
// DoAction per timeline frame, DoInitAction keyed by sprite, sprite timelines
// that keep their own frames and actions, CLIPACTIONS attached to placements,
// and the action-side tally. Also pins that frame-1 display-list behavior and
// its counters are unchanged. Synthetic fixtures only.

import Foundation
@testable import opensky
import Testing

struct SWFActionMovieTests {
    private static let red = SWFColor(red: 255, green: 0, blue: 0, alpha: 255)

    private static func shapeTag(_ characterId: UInt16) -> SWFFixture.Tag {
        SWFDisplayFixture.rectangleShapeTag(
            characterId: characterId, width: 1000, height: 1000, color: red
        )
    }

    private static func place(_ characterId: UInt16, depth: UInt16) -> SWFDisplayFixture.Place2 {
        var place = SWFDisplayFixture.Place2()
        place.depth = depth
        place.characterId = characterId
        return place
    }

    @Test func doActionLandsOnTheFrameItBelongsTo() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x07)]),
            SWFDisplayFixture.showFrameTag,
            SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x06)]),
            SWFActionFixture.doActionTag([SWFActionFixture.gotoFrame(0)]),
            SWFDisplayFixture.showFrameTag
        ])

        #expect(movie.timeline.frames.count == 2)
        #expect(movie.timeline.frames[0].actions.count == 1)
        #expect(movie.timeline.frames[0].actions[0].records.map(\.code) == [0x07])
        #expect(movie.timeline.frames[1].actions.count == 2)
        #expect(movie.timeline.frames[1].actions[1].records[0].operands == .gotoFrame(0))
        #expect(movie.actionBlocks.count == 3)
    }

    @Test func doInitActionIsKeyedBySpriteId() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.showFrameTag
            ]),
            SWFActionFixture.doInitActionTag(spriteId: 30, [
                SWFActionFixture.push([.string("registerClass")]),
                SWFActionFixture.noOperands(0x52)
            ]),
            SWFDisplayFixture.showFrameTag
        ])

        #expect(movie.initActions.count == 1)
        #expect(movie.initActions[0].spriteId == 30)
        #expect(movie.initActions[0].actions.records.map(\.code) == [0x96, 0x52])
        #expect(
            movie.initActions[0].actions.records[0].operands == .push([.string("registerClass")])
        )
    }

    @Test func spriteKeepsItsOwnFramesAndActions() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            Self.shapeTag(10),
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 2, tags: [
                SWFDisplayFixture.placeObject2Tag(Self.place(10, depth: 1)),
                SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x07)]),
                SWFDisplayFixture.showFrameTag,
                SWFDisplayFixture.removeObject2Tag(depth: 1),
                SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x06)]),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(Self.place(30, depth: 3)),
            SWFDisplayFixture.showFrameTag
        ])
        let sprite = try #require(movie.sprite(30))

        // Frame 1 stays exactly what milestone 8.2.4 produced.
        #expect(sprite.frame1.count == 1)
        #expect(sprite.frame1.first?.characterId == 10)
        // The later frame is now retained instead of discarded.
        #expect(sprite.timeline.frames.count == 2)
        #expect(sprite.timeline.frames[0].actions.count == 1)
        #expect(
            sprite.timeline.frames[1].steps
                == [.remove(SWFRemoval(depth: 1, characterId: nil))]
        )
        #expect(sprite.timeline.frames[1].actions[0].records.map(\.code) == [0x06])
        #expect(movie.actionBlocks.count == 2)
    }

    @Test func clipActionsDecodeEveryHandler() throws {
        let press = SWFActionFixture.stream(
            [SWFActionFixture.push([.string("onPress")])], appendEnd: false
        )
        let enterFrame = SWFActionFixture.stream(
            [SWFActionFixture.noOperands(0x07)], appendEnd: false
        )
        var place = Self.place(30, depth: 1)
        place.clipActions = SWFActionFixture.clipActions(
            version: 6,
            allEvents: [.press, .enterFrame],
            handlers: [
                SWFActionFixture.ClipHandler(events: [.press], actions: press),
                SWFActionFixture.ClipHandler(events: [.enterFrame], actions: enterFrame)
            ]
        )
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ])
        guard case let .place(placement) = movie.timeline.frames.first?.steps.first else {
            Issue.record("expected a placement step: \(movie.timeline.frames)")
            return
        }
        let clip = try #require(placement.clipActions)

        #expect(placement.hasClipActions)
        #expect(clip.allEvents == [.press, .enterFrame])
        #expect(clip.records.count == 2)
        #expect(clip.records[0].events == [.press])
        #expect(clip.records[0].keyCode == nil)
        #expect(clip.records[0].actions.records[0].operands == .push([.string("onPress")]))
        #expect(clip.records[1].events == [.enterFrame])
        #expect(clip.records[1].actions.records.map(\.code) == [0x07])
        #expect(clip.warnings.isEmpty)
        #expect(movie.tally.clipActions == 1)
    }

    @Test func clipActionsCarryTheKeyPressKeyCode() throws {
        var place = Self.place(30, depth: 1)
        place.clipActions = SWFActionFixture.clipActions(
            version: 6,
            allEvents: [.keyPress],
            handlers: [
                SWFActionFixture.ClipHandler(
                    events: [.keyPress],
                    keyCode: 13,
                    actions: SWFActionFixture.stream(
                        [SWFActionFixture.noOperands(0x07)], appendEnd: false
                    )
                )
            ]
        )
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject3Tag(SWFDisplayFixture.Place3(place: place)),
            SWFDisplayFixture.showFrameTag
        ])
        guard case let .place(placement) = movie.timeline.frames.first?.steps.first else {
            Issue.record("expected a placement step")
            return
        }
        let clip = try #require(placement.clipActions)

        #expect(clip.records.count == 1)
        #expect(clip.records[0].keyCode == 13)
        #expect(clip.records[0].actions.records.map(\.code) == [0x07])
        #expect(movie.tally.placeObject3 == 1)
    }

    @Test func clipEventFlagsUseTheNarrowWordBeforeSWF6() throws {
        var place = Self.place(30, depth: 1)
        place.clipActions = SWFActionFixture.clipActions(
            version: 5,
            allEvents: [.load],
            handlers: [
                SWFActionFixture.ClipHandler(
                    events: [.load],
                    actions: SWFActionFixture.stream(
                        [SWFActionFixture.noOperands(0x07)], appendEnd: false
                    )
                )
            ]
        )
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ], version: 5)
        guard case let .place(placement) = movie.timeline.frames.first?.steps.first else {
            Issue.record("expected a placement step")
            return
        }
        let clip = try #require(placement.clipActions)

        #expect(movie.version == 5)
        #expect(clip.allEvents == [.load])
        #expect(clip.records.count == 1)
        #expect(clip.warnings.isEmpty)
    }

    @Test func malformedClipActionsKeepThePlacement() throws {
        var place = Self.place(30, depth: 1)
        // Reserved UI16 and a flag word, then a record whose ActionRecordSize
        // runs past the end of the tag body.
        place.clipActions = Data([0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 0xFF, 0xFF, 0, 0])
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ])
        guard case let .place(placement) = movie.timeline.frames.first?.steps.first else {
            Issue.record("expected a placement step")
            return
        }
        let clip = try #require(placement.clipActions)

        #expect(movie.frame1.map(\.characterId) == [30])
        #expect(clip.records.isEmpty)
        #expect(clip.warnings.count == 1)
        #expect(movie.tally.actionWarnings == 1)
        #expect(movie.tally.danglingPlacements == 0)
    }

    @Test func tallyCountsActionsAcrossTheWholeMovie() throws {
        let movie = try SWFDisplayFixture.movie(tags: [
            SWFDisplayFixture.spriteTag(characterId: 30, frameCount: 1, tags: [
                SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x07)]),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFActionFixture.doInitActionTag(spriteId: 30, [
                SWFActionFixture.noOperands(0x06)
            ]),
            SWFActionFixture.doActionTag([
                SWFActionFixture.push([.integer(1)]),
                SWFActionFixture.noOperands(0x9E), // ActionCall: known, no typed decode
                SWFActionFixture.noOperands(0x77), // not in the Adobe table
                SWFActionFixture.Action(code: 0xB1, operands: Data([9])) // framed only
            ]),
            SWFDisplayFixture.showFrameTag
        ])

        #expect(movie.tally.actionBlocks == 3)
        #expect(movie.tally.actionRecords == 6)
        #expect(movie.tally.unknownActionOpcodes == 2)
        #expect(movie.tally.undecodedActionOpcodes == 1)
        #expect(movie.tally.actionWarnings == 0)
        #expect(movie.tally.sprites == 1)
    }

    @Test func actionsDoNotDisturbTheFrame1DisplayList() throws {
        let withActions = try SWFDisplayFixture.movie(tags: [
            Self.shapeTag(10),
            SWFActionFixture.doActionTag([SWFActionFixture.noOperands(0x07)]),
            SWFDisplayFixture.placeObject2Tag(Self.place(10, depth: 1)),
            SWFDisplayFixture.showFrameTag,
            SWFDisplayFixture.placeObject2Tag(Self.place(10, depth: 2)),
            SWFDisplayFixture.showFrameTag
        ])

        #expect(withActions.frame1.map(\.depth) == [1])
        #expect(withActions.tally.showFrames == 1)
        #expect(withActions.tally.placeObject2 == 1)
        #expect(withActions.timeline.frames.count == 2)
        #expect(withActions.timeline.frames[1].steps.count == 1)
    }
}
