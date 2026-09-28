// Hit testing, pointer routing, and key routing (milestone 8.3.2 phase 3).
// Device-free, synthetic fixtures only — no test reads a real `.swf`
// (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import simd
import Testing

struct SWFRuntimeInputTests {
    /// A movie with a 2000x1200 twip rectangle inside a sprite named `button`,
    /// placed at (400, 300) twips, plus a second sprite named `plate` behind it.
    private static func buttonTags(
        buttonScale: Float? = nil,
        clipDepth: UInt16? = nil
    ) -> [SWFFixture.Tag] {
        var button = SWFDisplayFixture.Place2()
        button.depth = 4
        button.characterId = 3
        button.name = "button"
        button.matrix = SWFDisplayFixture.MatrixSpec(
            scaleX: buttonScale, scaleY: buttonScale, translateX: 400, translateY: 300
        )
        var mask = SWFDisplayFixture.Place2()
        mask.depth = 2
        mask.characterId = 1
        mask.name = "mask"
        mask.clipDepth = clipDepth
        mask.matrix = SWFDisplayFixture.MatrixSpec(translateX: 0, translateY: 0)
        return [
            SWFRuntimeFixture.rectangle(id: 1, width: 1000, height: 1000),
            SWFRuntimeFixture.rectangle(id: 2, width: 2000, height: 1200),
            SWFDisplayFixture.spriteTag(characterId: 3, frameCount: 1, tags: [
                SWFRuntimeFixture.place(2, depth: 1), SWFDisplayFixture.showFrameTag
            ])
        ]
            + (clipDepth == nil ? [] : [SWFDisplayFixture.placeObject2Tag(mask)])
            + [SWFDisplayFixture.placeObject2Tag(button), SWFDisplayFixture.showFrameTag]
    }

    /// Installs a Swift-backed handler on a node so a test can see the routing
    /// without writing bytecode for it.
    @discardableResult
    private func record(
        _ runtime: SWFMovieRuntime,
        on node: SWFDisplayObject,
        _ name: String,
        into log: RoutingLog,
        returning result: AS2Value = .undefined
    ) -> SWFDisplayObject {
        AS2Natives.method(runtime.runtime, on: node.object, name: name) { _ in
            log.append(name)
            return result
        }
        return node
    }

    /// A reference box so a `@Sendable` native body can append to it.
    final class RoutingLog: @unchecked Sendable {
        private(set) var entries: [String] = []

        func append(_ entry: String) {
            entries.append(entry)
        }
    }

    private func startedButton(
        buttonScale: Float? = nil,
        clipDepth: UInt16? = nil
    ) throws -> (SWFMovieRuntime, SWFDisplayObject) {
        let runtime = try SWFRuntimeFixture.started(
            tags: Self.buttonTags(buttonScale: buttonScale, clipDepth: clipDepth)
        )
        let button = try #require(runtime.root.child(named: "button"))
        return (runtime, button)
    }

    // MARK: - Hit testing

    /// The rectangle covers (400,300) to (2400,1500) twips, which is (20,15) to
    /// (120,75) pixels. A clip becomes a mouse target only once it carries a
    /// handler.
    @Test func hitTestingFindsTheTopmostMouseEnabledObject() throws {
        let (runtime, button) = try startedButton()
        #expect(runtime.isMouseEnabled(button) == false)
        var result = runtime.hitTest(stageTwips: SIMD2(1000, 800))
        #expect(result.target == nil)
        #expect(result.topmost !== nil)

        record(runtime, on: button, "onPress", into: RoutingLog())
        #expect(runtime.isMouseEnabled(button))
        result = runtime.hitTest(stageTwips: SIMD2(1000, 800))
        #expect(result.target === button)
        // Outside the rectangle in both axes.
        #expect(runtime.hitTest(stageTwips: SIMD2(3000, 800)).target == nil)
        #expect(runtime.hitTest(stageTwips: SIMD2(1000, 100)).target == nil)
    }

    /// A scaled placement moves the hit area with the artwork, because the point
    /// is carried into the node's local space rather than the box being scaled.
    @Test func hitTestingRespectsTheTransformChain() throws {
        let (runtime, button) = try startedButton(buttonScale: 2)
        record(runtime, on: button, "onPress", into: RoutingLog())
        // Half scale would miss; at 2x the rectangle reaches 4400 twips.
        #expect(runtime.hitTest(stageTwips: SIMD2(4000, 2000)).target === button)
        #expect(runtime.hitTest(stageTwips: SIMD2(4600, 2000)).target == nil)
    }

    @Test func anInvisibleObjectCatchesNothing() throws {
        let (runtime, button) = try startedButton()
        record(runtime, on: button, "onPress", into: RoutingLog())
        #expect(runtime.hitTest(stageTwips: SIMD2(1000, 800)).target === button)
        button.isVisible = false
        #expect(runtime.hitTest(stageTwips: SIMD2(1000, 800)).target == nil)
        #expect(runtime.hitTest(stageTwips: SIMD2(1000, 800)).topmost == nil)
    }

    /// A clip layer masks the depths above it: the button is only hit where the
    /// 400x400 twip mask covers it.
    @Test func aClipLayerLimitsTheHitAreaOfWhatItMasks() throws {
        let (runtime, button) = try startedButton(clipDepth: 8)
        record(runtime, on: button, "onPress", into: RoutingLog())
        // The mask covers 0...1000 twips; the button spans 400...2400.
        #expect(runtime.hitTest(stageTwips: SIMD2(500, 400)).target === button)
        // Inside the button but outside the mask.
        #expect(runtime.hitTest(stageTwips: SIMD2(1200, 900)).target == nil)
    }

    // MARK: - Pointer routing

    @Test func pointerMovementRoutesRolloverAndRollout() throws {
        let (runtime, button) = try startedButton()
        let log = RoutingLog()
        record(runtime, on: button, "onRollOver", into: log)
        record(runtime, on: button, "onRollOut", into: log)
        #expect(runtime.handle(.pointerMoved(x: 50, y: 40)))
        #expect(log.entries == ["onRollOver"])
        // Moving inside the same object sends nothing new.
        runtime.handle(.pointerMoved(x: 60, y: 45))
        #expect(log.entries == ["onRollOver"])
        runtime.handle(.pointerMoved(x: 400, y: 400))
        #expect(log.entries == ["onRollOver", "onRollOut"])
    }

    @Test func pressAndReleaseOverTheSameObjectRoutesRelease() throws {
        let (runtime, button) = try startedButton()
        let log = RoutingLog()
        record(runtime, on: button, "onPress", into: log)
        record(runtime, on: button, "onRelease", into: log)
        record(runtime, on: button, "onReleaseOutside", into: log)
        runtime.handle(.pointerPressed(x: 50, y: 40))
        #expect(log.entries == ["onPress"])
        runtime.handle(.pointerReleased(x: 55, y: 45))
        #expect(log.entries == ["onPress", "onRelease"])
    }

    @Test func releasingAwayFromTheObjectRoutesReleaseOutside() throws {
        let (runtime, button) = try startedButton()
        let log = RoutingLog()
        record(runtime, on: button, "onPress", into: log)
        record(runtime, on: button, "onRelease", into: log)
        record(runtime, on: button, "onReleaseOutside", into: log)
        record(runtime, on: button, "onDragOut", into: log)
        runtime.handle(.pointerPressed(x: 50, y: 40))
        runtime.handle(.pointerMoved(x: 400, y: 400))
        runtime.handle(.pointerReleased(x: 400, y: 400))
        #expect(log.entries == ["onPress", "onDragOut", "onReleaseOutside"])
    }

    /// `onMouseDown` is global in Flash: a clip that defines one is called
    /// wherever the pointer is, unlike `onPress`.
    @Test func mouseDownReachesEveryClipRegardlessOfThePointer() throws {
        let (runtime, button) = try startedButton()
        let log = RoutingLog()
        #expect(runtime.globalMouseHandlerClips == 0)
        record(runtime, on: button, "onMouseDown", into: log)
        #expect(runtime.globalMouseHandlerClips == 1)
        runtime.handle(.pointerPressed(x: 400, y: 400))
        #expect(log.entries == ["onMouseDown"])
    }

    @Test func globalMouseHandlerIndexTracksPrototypeMutations() throws {
        let (runtime, button) = try startedButton()
        let log = RoutingLog()
        let prototype = runtime.runtime.makeObject()
        button.object.prototype = prototype
        #expect(runtime.globalMouseHandlerClips == 0)

        AS2Natives.method(runtime.runtime, on: prototype, name: "onMouseMove") { _ in
            log.append("onMouseMove")
            return .undefined
        }
        #expect(runtime.globalMouseHandlerClips == 1)
        #expect(runtime.handle(.pointerMoved(x: 400, y: 400)))
        #expect(log.entries == ["onMouseMove"])

        #expect(prototype.removeProperty("onMouseMove"))
        #expect(runtime.globalMouseHandlerClips == 0)
        #expect(runtime.handle(.pointerMoved(x: 410, y: 410)) == false)
    }

    @Test func mousePositionIsReportedInTheNodesOwnSpace() throws {
        let (runtime, button) = try startedButton()
        runtime.handle(.pointerMoved(x: 50, y: 40))
        #expect(runtime.displayProperty(.mouseX, of: runtime.root) == .number(50))
        #expect(runtime.displayProperty(.mouseY, of: runtime.root) == .number(40))
        // The button sits at (400, 300) twips, which is (20, 15) pixels.
        #expect(runtime.displayProperty(.mouseX, of: button) == .number(30))
        #expect(runtime.displayProperty(.mouseY, of: button) == .number(25))
    }

    // MARK: - Keys and focus

    @Test func anUnconsumedKeyFallsBackToTheFocusedObject() throws {
        let (runtime, button) = try startedButton()
        let log = RoutingLog()
        record(runtime, on: button, "onKeyDown", into: log)
        #expect(runtime.handle(.keyDown(code: SWFKeyCode.down, ascii: 0)) == false)
        #expect(runtime.setFocus(.object(button.object)))
        #expect(runtime.focusTarget === button)
        #expect(runtime.handle(.keyDown(code: SWFKeyCode.down, ascii: 0)))
        #expect(log.entries == ["onKeyDown"])
    }

    /// The Bethesda menu-root convention: the outermost clip that defines
    /// `handleInput` receives the navigation event, with the movie's own
    /// `NavigationCode` spelling when it ships one.
    @Test func navigationReachesTheMenusOwnHandleInput() throws {
        let (runtime, button) = try startedButton()
        let log = RoutingLog()
        record(runtime, on: button, "handleInput", into: log, returning: .boolean(true))
        #expect(runtime.menuInputHandler === button)
        #expect(runtime.handle(.keyDown(code: SWFKeyCode.up, ascii: 0)))
        #expect(log.entries == ["handleInput"])
        // A key release is not routed to `handleInput`; one press is one event.
        runtime.handle(.keyUp(code: SWFKeyCode.up))
        #expect(log.entries == ["handleInput"])
    }

    @Test func inputDetailsCarryTheCodeAndTheNavigationEquivalent() throws {
        let (runtime, _) = try startedButton()
        // Without the movie's `NavigationCode`, the equivalent is absent rather
        // than invented.
        #expect(runtime.navigationEquivalent(forKey: SWFKeyCode.up) == nil)
        let codes = runtime.runtime.makeObject()
        codes.define(.string("up"), for: "UP")
        let ui = runtime.runtime.makeObject()
        ui.define(.object(codes), for: "NavigationCode")
        let gfx = runtime.runtime.makeObject()
        gfx.define(.object(ui), for: "ui")
        runtime.runtime.globalObject.define(.object(gfx), for: "gfx")
        #expect(runtime.navigationEquivalent(forKey: SWFKeyCode.up) == "up")

        let details = try #require(
            runtime.makeInputDetails(code: SWFKeyCode.up, value: "keyDown")?.objectValue
        )
        #expect(details.lookup("type")?.property.value == .string("key"))
        #expect(details.lookup("code")?.property.value == .number(38))
        #expect(details.lookup("value")?.property.value == .string("keyDown"))
        #expect(details.lookup("navEquivalent")?.property.value == .string("up"))
    }

    // MARK: - Viewport mapping

    /// A movie letterboxed into a wider viewport: the bars belong to no part of
    /// the movie, and the centre maps to the centre.
    @Test func viewportPointsMapIntoStagePixels() {
        let frame = SWFRect(xMin: 0, xMax: 8000, yMin: 0, yMax: 6000)
        let viewport = SIMD2<Float>(800, 300)
        // Uniform fit is 300/300 = 1 pixel per 20 twips, so the movie occupies
        // 400x300 pixels centred in 800x300.
        let centre = SWFInputMapping.stagePoint(
            viewportPoint: SIMD2(400, 150), frameSize: frame, viewportPixels: viewport
        )
        #expect(abs((centre?.x ?? 0) - 200) < 0.001)
        #expect(abs((centre?.y ?? 0) - 150) < 0.001)
        #expect(
            SWFInputMapping.stagePoint(
                viewportPoint: SIMD2(10, 150), frameSize: frame, viewportPixels: viewport
            ) == nil
        )
    }

    @Test func aFrameOriginOffsetIsFoldedIntoTheMapping() {
        let frame = SWFRect(xMin: -1000, xMax: 7000, yMin: -500, yMax: 5500)
        let mapped = SWFInputMapping.stagePoint(
            viewportPoint: SIMD2(0, 0), frameSize: frame, viewportPixels: SIMD2(400, 300)
        )
        #expect(abs(mapped?.x ?? 1) < 0.001)
        #expect(abs(mapped?.y ?? 1) < 0.001)
    }
}
