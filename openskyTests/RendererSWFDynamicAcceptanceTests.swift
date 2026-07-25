// Metal-gated pixel evidence for the M8.3.2 dynamic-render acceptance (todo
// 8.3.2 phase 2). The fixture reproduces the vanilla frame-1 pattern in code —
// content placed behind an alpha-zero CXFORM, revealed only by the movie's own
// ActionScript — because 1,032 of the 1,902 frame-1 draws across the install
// resolve to alpha 0 and 20 of the 53 movies change no pixels at all until
// their script runs.
//
// The acceptance points: bringing the AS2 runtime up turns a zero-pixel frame
// into a many-pixel frame, a movie that is never ticked still renders
// byte-identically (the determinism contract, now expressed as "advances only
// on an explicit tick"), and a display list that outgrows the initial ring
// capacity grows the ring instead of dropping draws.
//
// Every movie is synthetic and built in code — never an extracted game file
// (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

/// A menu-shaped movie whose whole frame-1 content sits under one alpha-zero
/// clip named `panel`, plus a frame-1 `DoAction` that sets `panel._alpha = 100`.
private enum SWFDynamicFixture {
    static let plate = SWFColor(red: 40, green: 40, blue: 60, alpha: 255)
    static let accent = SWFColor(red: 30, green: 200, blue: 120, alpha: 255)

    /// CXFORM multiplying alpha by zero (terms are 8.8 fixed, 256 == 1.0).
    private static var alphaZero: SWFDisplayFixture.CxformSpec {
        SWFDisplayFixture.CxformSpec(multiplyTerms: [256, 256, 256, 0], addTerms: nil, nbits: 12)
    }

    /// `panel._alpha = 100`.
    private static var revealAction: SWFFixture.Tag {
        SWFActionFixture.doActionTag([
            AS2Fixture.push([.string("panel")]), AS2Fixture.opcode(0x1C),
            AS2Fixture.push([.string("_alpha"), .integer(100)]),
            AS2Fixture.opcode(0x4F)
        ])
    }

    static func scene(revealing: Bool) throws -> SWFMovieScene {
        try SWFMovieScene(movie: SWFDisplayFixture.movie(tags: tags(revealing: revealing)))
    }

    static func tags(revealing: Bool) -> [SWFFixture.Tag] {
        var panel = SWFDisplayFixture.Place2()
        panel.depth = 1
        panel.characterId = 3
        panel.name = "panel"
        panel.cxform = alphaZero
        panel.matrix = SWFDisplayFixture.MatrixSpec(translateX: 300, translateY: 300)
        return [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 6000, height: 4000, color: plate
            ),
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 2, width: 2400, height: 1600, color: accent
            ),
            SWFDisplayFixture.spriteTag(characterId: 3, frameCount: 1, tags: [
                SWFRuntimeFixture.place(1, depth: 1),
                SWFRuntimeFixture.place(2, depth: 2, translateX: 1200, translateY: 900),
                SWFDisplayFixture.showFrameTag
            ]),
            SWFDisplayFixture.placeObject2Tag(panel)
        ] + (revealing ? [revealAction] : []) + [SWFDisplayFixture.showFrameTag]
    }

    /// A movie whose second frame places `count` more rectangles, so one tick
    /// pushes the command stream past the ring capacity the first frame sized.
    static func growingScene(count: Int) throws -> SWFMovieScene {
        var tags: [SWFFixture.Tag] = [
            SWFDisplayFixture.rectangleShapeTag(
                characterId: 1, width: 200, height: 200, color: accent
            ),
            SWFRuntimeFixture.place(1, depth: 1),
            SWFDisplayFixture.showFrameTag
        ]
        for index in 0 ..< count {
            tags.append(SWFRuntimeFixture.place(
                1,
                depth: UInt16(index + 2),
                translateX: Int32(index % 20) * 300,
                translateY: Int32(index / 20) * 300
            ))
        }
        tags.append(SWFDisplayFixture.showFrameTag)
        return try SWFMovieScene(movie: SWFDisplayFixture.movie(tags: tags))
    }
}

struct RendererSWFDynamicAcceptanceTests {
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

    /// The milestone's pixel evidence: the same movie renders nothing at frame
    /// 1 and a full panel once its ActionScript runs.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func actionScriptRevealsContentHiddenByAnAlphaZeroColorTransform() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: true))
        let hidden = try Self.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls == 2, "frame 1 should still encode its draws")
        let hiddenChanged = Self.changedPixels(base, hidden)
        #expect(hiddenChanged == 0, "alpha-zero frame 1 changed \(hiddenChanged) pixels")

        let runtime = try #require(try renderer.startSWFRuntime())
        let revealed = try Self.render(renderer)
        let revealedChanged = Self.changedPixels(base, revealed)
        // Measured 68,160 changed pixels at 480x320; the threshold leaves room
        // for driver-level rasterization differences.
        #expect(revealedChanged > 60000, "the runtime revealed only \(revealedChanged) pixels")
        #expect(renderer.lastSWFDrawStats.skippedItems == 0)
        #expect(runtime.tally.faultTotal == 0)
    }

    /// The same movie without its `DoAction` stays blank after bring-up, which
    /// proves the pixels above came from the ActionScript and not from merely
    /// running the runtime.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aMovieWithoutTheRevealActionStaysBlank() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: false))
        try renderer.startSWFRuntime()
        let rendered = try Self.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls == 2)
        #expect(Self.changedPixels(base, rendered) == 0)
    }

    /// Determinism survives the dynamic path: the layer moves only when
    /// something ticks it, so repeated frames of an un-ticked movie are
    /// byte-identical.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func framesAreByteIdenticalWhileTheRuntimeIsNotAdvanced() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: true))
        try renderer.startSWFRuntime()
        _ = try Self.render(renderer)
        let first = try Self.render(renderer)
        let second = try Self.render(renderer)
        #expect(first == second)
        // Advancing a one-frame movie changes nothing either, because the
        // playhead has nowhere to go.
        try renderer.advanceSWFRuntime()
        #expect(try Self.render(renderer) == first)
    }

    /// The rings are sized for the current stream plus headroom; a tick that
    /// places far more content grows them rather than dropping draws.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aGrowingDisplayListGrowsTheRingsInsteadOfDroppingDraws() throws {
        let renderer = try Self.makeRenderer()
        try renderer.setSWFMovie(SWFDynamicFixture.growingScene(count: 200))
        try renderer.startSWFRuntime()
        _ = try Self.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls == 1)
        try renderer.advanceSWFRuntime()
        _ = try Self.render(renderer)
        let stats = renderer.lastSWFDrawStats
        #expect(stats.drawCalls == 201, "encoded \(stats.drawCalls) of 201 draws")
        #expect(stats.skippedItems == 0, "\(stats.skippedItems) draws were dropped")
    }

    /// Dropping the runtime restores the movie's static frame-1 stream, so the
    /// A/B against the static acceptance stays available.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func stoppingTheRuntimeRestoresTheStaticFrame() throws {
        let renderer = try Self.makeRenderer()
        let base = try Self.render(renderer)
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: true))
        let hidden = try Self.render(renderer)
        try renderer.startSWFRuntime()
        #expect(try Self.changedPixels(base, Self.render(renderer)) > 2000)
        try renderer.stopSWFRuntime()
        #expect(renderer.swfRuntime == nil)
        #expect(try Self.render(renderer) == hidden)
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
