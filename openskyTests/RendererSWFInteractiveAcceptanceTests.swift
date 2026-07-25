// Metal-gated pixel evidence for the M8.3.3 interactive acceptance: a simulated
// input event changes the rendered frame.
//
// The fixture is the vanilla interaction shape reduced to its smallest form —
// content hidden behind an alpha-zero CXFORM, revealed by a handler the movie's
// own ActionScript attaches to a display object. Pointer routing reaches it
// through `onRollOver` on the object under the cursor, which is what CLIK's
// `gfx.controls.Button` assigns; key routing reaches it through
// `handleInput(details, pathToFocus)`, which is what every vanilla menu class
// defines.
//
// Every movie is synthetic and built in code — never an extracted game file
// (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

/// A movie whose `highlight` clip is hidden by an alpha-zero CXFORM and whose
/// `button` clip carries the handlers that reveal it.
private enum SWFInteractiveFixture {
    typealias Action = AS2Fixture.Action

    static let plate = SWFColor(red: 30, green: 200, blue: 120, alpha: 255)
    static let ink = SWFColor(red: 220, green: 180, blue: 90, alpha: 255)

    private static var alphaZero: SWFDisplayFixture.CxformSpec {
        SWFDisplayFixture.CxformSpec(multiplyTerms: [256, 256, 256, 0], addTerms: nil, nbits: 12)
    }

    /// `_root.highlight._alpha = 100`.
    private static var revealBody: [Action] {
        [
            AS2Fixture.push([.string("_root")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("highlight")]), AS2Fixture.opcode(0x4E),
            AS2Fixture.push([.string("_alpha"), .integer(100)]),
            AS2Fixture.opcode(0x4F)
        ]
    }

    /// `button.<name> = function () { …reveal… }`, as an anonymous function
    /// literal assigned to a member.
    private static func assignHandler(_ name: String, returningTrue: Bool) -> [Action] {
        var body = revealBody
        if returningTrue {
            body += [AS2Fixture.push([.boolean(true)]), AS2Fixture.opcode(0x3E)]
        }
        let define = SWFActionFixture.defineFunction(
            name: "", parameters: [], bodySize: UInt16(AS2Fixture.size(body))
        )
        return [
            AS2Fixture.push([.string("button")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string(name)]),
            define
        ] + body + [AS2Fixture.opcode(0x4F)]
    }

    static func scene() throws -> SWFMovieScene {
        try SWFMovieScene(movie: SWFDisplayFixture.movie(tags: tags()))
    }

    static func tags() -> [SWFFixture.Tag] {
        var highlight = SWFDisplayFixture.Place2()
        highlight.depth = 1
        highlight.characterId = 2
        highlight.name = "highlight"
        highlight.cxform = alphaZero
        highlight.matrix = SWFDisplayFixture.MatrixSpec(translateX: 200, translateY: 200)

        var button = SWFDisplayFixture.Place2()
        button.depth = 2
        button.characterId = 4
        button.name = "button"
        button.matrix = SWFDisplayFixture.MatrixSpec(translateX: 4000, translateY: 4000)

        return [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 7000, height: 3000, color: plate
            ),
            SWFDisplayFixture.spriteTag(characterId: 2, frameCount: 1, tags: [
                SWFRuntimeFixture.place(1, depth: 1), SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 3, width: 2000, height: 1200, color: ink
            ),
            SWFDisplayFixture.spriteTag(characterId: 4, frameCount: 1, tags: [
                SWFRuntimeFixture.place(3, depth: 1), SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(highlight),
            SWFDisplayFixture.placeObject2Tag(button),
            SWFActionFixture.doActionTag(
                assignHandler("onRollOver", returningTrue: false)
                    + assignHandler("handleInput", returningTrue: true)
            ),
            SWFDisplayFixture.showFrameTag
        ]
    }

    /// The centre of the button in stage pixels: (4000, 4000) twips plus half of
    /// a 2000x1200 twip rectangle, divided by 20.
    static let buttonCentre = (x: 250.0, y: 230.0)
    /// A point well outside the button but inside the stage.
    static let elsewhere = (x: 20.0, y: 20.0)
}

struct RendererSWFInteractiveAcceptanceTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let width = 480
    private static let height = 320
    private static let animationTime: Float = 1

    /// The milestone gate's pixel evidence: moving the pointer onto the button
    /// changes the frame, and moving it away from the button does not.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aPointerRolloverChangesTheRenderedFrame() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFInteractiveFixture.scene())
        let runtime = try #require(try renderer.startSWFRuntime())
        let closed = try Self.render(renderer)

        let missed = try renderer.sendSWFInput(
            .pointerMoved(
                x: SWFInteractiveFixture.elsewhere.x,
                y: SWFInteractiveFixture.elsewhere.y
            )
        )
        #expect(missed == false, "a pointer over nothing must not be consumed")
        #expect(try Self.changedPixels(closed, Self.render(renderer)) == 0)

        let hit = try renderer.sendSWFInput(
            .pointerMoved(
                x: SWFInteractiveFixture.buttonCentre.x,
                y: SWFInteractiveFixture.buttonCentre.y
            )
        )
        #expect(hit, "the pointer landed on the button but nothing consumed it")
        let opened = try Self.render(renderer)
        let changed = Self.changedPixels(closed, opened)
        // Measured 59,840 changed pixels at 480x320; the threshold leaves room
        // for driver-level rasterization differences.
        #expect(changed > 50000, "the rollover changed only \(changed) pixels")
        #expect(runtime.tally.faultTotal == 0)
        #expect(renderer.lastSWFDrawStats.skippedItems == 0)
    }

    /// The same movie, driven by a key instead: the navigation event reaches the
    /// menu's own `handleInput` and the frame changes the same way.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aKeyEventReachesTheMenuHandlerAndChangesTheFrame() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFInteractiveFixture.scene())
        try renderer.startSWFRuntime()
        let closed = try Self.render(renderer)
        let handled = try renderer.sendSWFInput(.keyDown(code: SWFKeyCode.down, ascii: 0))
        #expect(handled, "the key was not routed to the menu handler")
        let changed = try Self.changedPixels(closed, Self.render(renderer))
        #expect(changed > 50000, "the key changed only \(changed) pixels")
    }

    /// Determinism survives input: the layer moves only when something injects
    /// an event, so repeated frames between events are byte-identical.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func framesAreByteIdenticalBetweenInjectedEvents() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFInteractiveFixture.scene())
        try renderer.startSWFRuntime()
        try renderer.sendSWFInput(
            .pointerMoved(
                x: SWFInteractiveFixture.buttonCentre.x,
                y: SWFInteractiveFixture.buttonCentre.y
            )
        )
        _ = try Self.render(renderer)
        let first = try Self.render(renderer)
        #expect(try Self.render(renderer) == first)
        // Re-injecting the same position changes nothing: the pointer is
        // already on the button, so no rollover is sent.
        try renderer.sendSWFInput(
            .pointerMoved(
                x: SWFInteractiveFixture.buttonCentre.x,
                y: SWFInteractiveFixture.buttonCentre.y
            )
        )
        #expect(try Self.render(renderer) == first)
    }

    /// The engine-to-movie half of the bridge, through the renderer seam the app
    /// uses. The movie defines no callback of this name, so the call degrades to
    /// a logged no-op — and the frame is untouched.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func anUnhandledBridgeCallLeavesTheFrameUntouched() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFInteractiveFixture.scene())
        let runtime = try #require(try renderer.startSWFRuntime())
        let before = try Self.render(renderer)
        #expect(try renderer.callSWFMovie("NoSuchCallback") == .undefined)
        #expect(try Self.render(renderer) == before)
        #expect(runtime.invokeLog.unhandled == 1)
        #expect(runtime.tally.missingNames["NoSuchCallback"] == 1)
    }

    // MARK: - Helpers

    @MainActor
    private static func makeRenderer() throws -> Renderer {
        let device = try #require(self.device)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(view: view)
    }

    @MainActor
    private static func render(_ renderer: Renderer) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(
            width: width, height: height, animationTime: animationTime
        )
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    /// Count of pixels differing beyond a small per-channel threshold.
    private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        var changed = 0
        for pixel in stride(from: 0, to: lhs.count, by: 4) {
            let delta = (0 ..< 3).map { abs(Int(lhs[pixel + $0]) - Int(rhs[pixel + $0])) }
                .max() ?? 0
            if delta > 8 {
                changed += 1
            }
        }
        return changed
    }
}
