// DefineButton2: records and conditions decode, the state timeline follows the
// pointer, and condition actions run on the parent timeline.

import Foundation
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFButtonTests {
    /// `clicked = 1` on the timeline the actions run in.
    private static let setClicked: [SWFActionFixture.Action] = [
        SWFActionFixture.push([.string("clicked"), .integer(1)]),
        SWFActionFixture.noOperands(0x1D)
    ]

    private static func buttonTags() -> [SWFFixture.Tag] {
        [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFRuntimeFixture.rectangle(id: 2, width: 3000, height: 1500),
            SWFButtonFixture.defineButton2Tag(
                characterId: 3,
                records: [
                    .init(states: [.up, .hitTest], characterId: 1, depth: 1),
                    .init(states: [.over, .down], characterId: 2, depth: 1)
                ],
                conditions: [
                    .init(transitions: 0x01, actions: []), // IdleToOverUp
                    .init(transitions: 0x08, actions: setClicked) // OverDownToOverUp
                ]
            ),
            SWFRuntimeFixture.place(3, depth: 1, name: "button"),
            SWFDisplayFixture.showFrameTag
        ]
    }

    @Test func decodesRecordsAndConditions() throws {
        let movie = try SWFDisplayFixture.movie(tags: Self.buttonTags())
        let button = try #require(movie.button(3))
        #expect(button.records.map(\.characterId) == [1, 2])
        #expect(button.records[0].states == [.up, .hitTest])
        #expect(button.conditions.map(\.events) == [.rollOver, .release])
        #expect(button.conditions[1].keyCode == nil)
        #expect(!button.trackAsMenu)
    }

    @Test func mapsEveryTransitionAndTheKeyByte() {
        #expect(SWFButton.events(transitions: 0x04, keyByte: 0) == .press)
        #expect(SWFButton.events(transitions: 0x40, keyByte: 0) == .releaseOutside)
        #expect(SWFButton.events(transitions: 0, keyByte: 0x01) == .dragOut)
        #expect(SWFButton.events(transitions: 0, keyByte: 13 << 1) == .keyPress)
    }

    @Test func theStateTimelineShowsOneStatePerFrame() throws {
        let movie = try SWFDisplayFixture.movie(tags: Self.buttonTags())
        let timeline = try #require(movie.button(3)).stateTimeline
        #expect(timeline.frameLabels == SWFButton.stateLabels)
        #expect(timeline.frame1.map(\.characterId) == [1])
    }

    @Test func thePointerMovesTheStateAndAReleaseRunsTheActionOnTheParent() throws {
        let runtime = try SWFRuntimeFixture.started(tags: Self.buttonTags())
        let button = try #require(runtime.root.child(named: "button"))
        #expect(button.isButton)
        #expect(button.child(atDepth: 1)?.characterId == 1)
        runtime.handle(.pointerMoved(x: 50, y: 40))
        #expect(button.child(atDepth: 1)?.characterId == 2)
        runtime.handle(.pointerPressed(x: 50, y: 40))
        runtime.handle(.pointerReleased(x: 50, y: 40))
        #expect(runtime.root.object.lookup("clicked")?.property.value == .number(1))
        runtime.handle(.pointerMoved(x: 390, y: 290))
        #expect(button.child(atDepth: 1)?.characterId == 1)
    }

    @Test func theStaticSceneDrawsTheUpState() throws {
        let movie = try SWFDisplayFixture.movie(tags: Self.buttonTags())
        let items = SWFRuntimeFixture.drawItems(SWFScene.build(movie: movie))
        #expect(items.map(\.content) == [.shape(1)])
    }
}
