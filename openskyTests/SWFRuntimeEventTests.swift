// Event dispatch, broadcasters, and timers (milestone 8.3.2 phase 3).
// Device-free, synthetic fixtures only — no test reads a real `.swf`
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

struct SWFRuntimeEventTests {
    typealias Action = AS2Fixture.Action

    /// `_root.log = _root.log + "<mark>"`, so a handler that runs leaves an
    /// ordered trace on the root timeline whichever clip it belongs to.
    private static func mark(_ text: String) -> [Action] {
        [
            AS2Fixture.push([.string("_root")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("log")]),
            AS2Fixture.push([.string("_root")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("log")]), AS2Fixture.opcode(0x4E),
            AS2Fixture.push([.string(text)]), AS2Fixture.opcode(0x47),
            AS2Fixture.opcode(0x4F)
        ]
    }

    /// `_root.log = ""`, so the first append is not a concatenation onto
    /// `undefined`.
    private static var resetLog: [Action] {
        [
            AS2Fixture.push([.string("_root")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("log"), .string("")]), AS2Fixture.opcode(0x4F)
        ]
    }

    private static func handler(
        _ events: SWFClipEventFlags,
        _ text: String,
        keyCode: UInt8? = nil
    ) -> SWFActionFixture.ClipHandler {
        SWFActionFixture.ClipHandler(
            events: events, keyCode: keyCode,
            actions: SWFActionFixture.stream(mark(text))
        )
    }

    private static func clipActions(
        _ handlers: [SWFActionFixture.ClipHandler]
    ) -> Data {
        SWFActionFixture.clipActions(
            version: 6,
            allEvents: handlers.reduce(SWFClipEventFlags(rawValue: 0)) { $0.union($1.events) },
            handlers: handlers
        )
    }

    /// A movie whose sprite is placed with the given CLIPACTIONS handlers.
    /// `removing` adds a second frame that takes the placement away again.
    private static func lifecycleTags(
        _ handlers: [SWFActionFixture.ClipHandler],
        removing: Bool = true
    ) -> [SWFFixture.Tag] {
        var place = SWFDisplayFixture.Place2()
        place.depth = 1
        place.characterId = 2
        place.name = "panel"
        place.clipActions = clipActions(handlers)
        return [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 1, tags: [
                SWFRuntimeFixture.place(1, depth: 1), SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.exportAssetsTag([(2, "PanelClip")]),
            SWFActionFixture.doInitActionTag(
                spriteId: 2,
                resetLog
                    + SWFRuntimeFixture.registerClass(name: "PanelClass", linkage: "PanelClip")
                    + mark("C")
            ),
            SWFDisplayFixture.placeObject2Tag(place),
            SWFDisplayFixture.showFrameTag
        ] + (removing ? [
            SWFDisplayFixture.removeObject2Tag(depth: 1), SWFDisplayFixture.showFrameTag
        ] : [])
    }

    private func log(_ runtime: SWFMovieRuntime) -> String {
        guard
            case let .string(text) = runtime.root.object.lookup("log")?.property.value ?? .undefined
        else {
            return ""
        }
        return text
    }

    // MARK: - CLIPACTIONS lifecycle

    /// The order the `ClipEventFlags` table implies: `initialize` before the
    /// registered class constructor, then `construct`, then `load`.
    @Test func clipEventsFireInLifecycleOrderAroundTheConstructor() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.lifecycleTags([
                Self.handler(.initialize, "I"),
                Self.handler(.construct, "S"),
                Self.handler(.load, "L")
            ])
        )
        // "C" is written by the DoInitAction block, which runs before frame 1.
        #expect(log(runtime) == "CISL")
    }

    @Test func removingAPlacementDispatchesUnload() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.lifecycleTags([Self.handler(.unload, "U")])
        )
        #expect(log(runtime) == "C")
        runtime.advance()
        #expect(log(runtime) == "CU")
        #expect(runtime.root.child(atDepth: 1) == nil)
    }

    @Test func enterFrameFiresOnEveryTickAndNotDuringBringUp() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.lifecycleTags([Self.handler(.enterFrame, "E")], removing: false)
        )
        // Bring-up places the clip but ticks nothing, so no enter frame yet.
        #expect(log(runtime) == "C")
        runtime.advance()
        runtime.advance()
        #expect(log(runtime) == "CEE")
    }

    /// A `keyPress` handler only runs for the key it traps, and the tree is only
    /// walked because a placement registered one.
    @Test func keyPressHandlersMatchOnTheTrappedKeyCode() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.lifecycleTags([
                Self.handler([.keyPress], "P", keyCode: UInt8(SWFKeyCode.enter)),
                Self.handler(.keyDown, "D")
            ])
        )
        #expect(runtime.keyClipHandlers == 1)
        runtime.handle(.keyDown(code: SWFKeyCode.escape, ascii: 0))
        #expect(log(runtime) == "CD")
        runtime.handle(.keyDown(code: SWFKeyCode.enter, ascii: 13))
        #expect(log(runtime) == "CDDP")
    }

    @Test func globalMouseClipActionsEnterTheHandlerIndex() throws {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.lifecycleTags([Self.handler(.mouseDown, "M")], removing: false)
        )
        #expect(runtime.globalMouseHandlerClips == 1)
        #expect(runtime.handle(.pointerPressed(x: 400, y: 400)))
        #expect(log(runtime) == "CM")
    }

    // MARK: - Broadcasters

    private func startedBroadcastRuntime() throws -> SWFMovieRuntime {
        try SWFRuntimeFixture.started(tags: [
            SWFRuntimeFixture.rectangle(id: 1),
            SWFRuntimeFixture.place(1, depth: 1),
            SWFDisplayFixture.showFrameTag
        ])
    }

    @Test func keyAndMouseAreInstalledAsBroadcasters() throws {
        let runtime = try startedBroadcastRuntime()
        let key = try #require(runtime.globalBroadcaster("Key"))
        #expect(key.lookup("addListener") != nil)
        #expect(key.lookup("removeListener") != nil)
        #expect(key.lookup("UP")?.property.value == .number(38))
        #expect(key.lookup("DELETEKEY")?.property.value == .number(46))
        #expect(runtime.globalBroadcaster("Mouse")?.lookup("show") != nil)
    }

    /// A listener added from Swift receives the message, and removing it stops
    /// delivery — the `addListener` / `removeListener` contract vanilla uses.
    @Test func listenersReceiveBroadcastsUntilTheyAreRemoved() throws {
        let runtime = try startedBroadcastRuntime()
        let key = try #require(runtime.globalBroadcaster("Key"))
        let listener = runtime.runtime.makeObject()
        var calls = 0
        AS2Natives.method(runtime.runtime, on: listener, name: "onKeyDown") { _ in
            calls += 1
            return .undefined
        }
        let add = try #require(key.lookup("addListener")?.property.value.functionValue)
        runtime.runtime.invoke(
            .object(add), thisValue: .object(key), arguments: [.object(listener)]
        )
        #expect(runtime.handle(.keyDown(code: SWFKeyCode.down, ascii: 0)))
        #expect(calls == 1)
        #expect(runtime.input.isDown(SWFKeyCode.down))

        let remove = try #require(key.lookup("removeListener")?.property.value.functionValue)
        runtime.runtime.invoke(
            .object(remove), thisValue: .object(key), arguments: [.object(listener)]
        )
        runtime.handle(.keyDown(code: SWFKeyCode.down, ascii: 0))
        #expect(calls == 1)
    }

    @Test func keyQueriesAnswerFromInjectedState() throws {
        let runtime = try startedBroadcastRuntime()
        runtime.handle(.keyDown(code: SWFKeyCode.enter, ascii: 13))
        let key = try #require(runtime.globalBroadcaster("Key"))
        let getCode = try #require(key.lookup("getCode")?.property.value.functionValue)
        let isDown = try #require(key.lookup("isDown")?.property.value.functionValue)
        #expect(
            runtime.runtime.invoke(.object(getCode), thisValue: .object(key)).value == .number(13)
        )
        #expect(
            runtime.runtime.invoke(
                .object(isDown), thisValue: .object(key), arguments: [.integer(13)]
            ).value == .boolean(true)
        )
        runtime.handle(.keyUp(code: SWFKeyCode.enter))
        #expect(runtime.input.isDown(SWFKeyCode.enter) == false)
    }

    // MARK: - Timers

    /// `setInterval(object, "method", ms)` fires from the explicit tick, never
    /// from a clock, and `clearInterval` stops it.
    @Test func intervalsFireOnTicksAndStopWhenCleared() throws {
        let runtime = try startedBroadcastRuntime()
        let target = runtime.runtime.makeObject()
        var calls = 0
        AS2Natives.method(runtime.runtime, on: target, name: "tick") { _ in
            calls += 1
            return .undefined
        }
        let identifier = runtime.timers.add(
            callee: .object(target), method: "tick", arguments: [],
            period: runtime.timerTicks(milliseconds: 1), repeats: true
        )
        #expect(identifier > 0)
        runtime.advance()
        runtime.advance()
        #expect(calls == 2)
        #expect(runtime.timers.remove(id: identifier))
        runtime.advance()
        #expect(calls == 2)
    }

    @Test func timeoutsFireOnceAndTheListIsBounded() throws {
        let runtime = try startedBroadcastRuntime()
        let target = runtime.runtime.makeObject()
        var calls = 0
        AS2Natives.method(runtime.runtime, on: target, name: "tick") { _ in
            calls += 1
            return .undefined
        }
        _ = runtime.timers.add(
            callee: .object(target), method: "tick", arguments: [], period: 1, repeats: false
        )
        runtime.advance()
        runtime.advance()
        #expect(calls == 1)
        #expect(runtime.timers.isEmpty)

        for _ in 0 ..< (SWFRuntimeTimers.maximumTimers + 4) {
            _ = runtime.timers.add(
                callee: .object(target), method: "tick", arguments: [],
                period: 1000, repeats: true
            )
        }
        #expect(runtime.timers.count == SWFRuntimeTimers.maximumTimers)
        #expect(runtime.timers.dropped == 4)
    }

    /// A millisecond interval becomes a whole number of ticks against the
    /// movie's own declared frame rate, and never zero.
    @Test func millisecondsConvertToTicksAgainstTheMovieFrameRate() throws {
        let runtime = try startedBroadcastRuntime()
        #expect(runtime.movie.frameRate == 24)
        #expect(runtime.timerTicks(milliseconds: 1) == 1)
        #expect(runtime.timerTicks(milliseconds: 1000) == 24)
        #expect(runtime.timerTicks(milliseconds: .nan) == 1)
        #expect(runtime.timerTicks(milliseconds: 1e12) == SWFMovieRuntime.maximumTimerTicks)
    }
}
