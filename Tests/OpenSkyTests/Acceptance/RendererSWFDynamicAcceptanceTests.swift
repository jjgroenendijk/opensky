// Dynamic SWF acceptance in pixels. Content sits behind an alpha-zero colour
// transform until the movie's own ActionScript reveals it, as most vanilla
// menus do at frame 1. Starting the runtime turns a blank frame into a full
// one, an unticked movie repeats byte for byte, and a display list larger than
// the ring grows the ring instead of dropping draws. Movies are built in code.

import Foundation
import Metal
import OpenSkyEngineTesting
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
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

@Suite(.tags(.acceptance, .gpu))
struct RendererSWFDynamicAcceptanceTests {
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let canvas = OffscreenCanvas(width: 480, height: 320, shaders: .appBundle)

    /// The milestone's pixel evidence: the same movie renders nothing at frame
    /// 1 and a full panel once its ActionScript runs.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func actionScriptRevealsContentHiddenByAnAlphaZeroColorTransform() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: true))
        let hidden = try Self.canvas.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls == 2, "frame 1 should still encode its draws")
        let hiddenChanged = OffscreenRendererFixture.changedPixels(base, hidden)
        #expect(hiddenChanged == 0, "alpha-zero frame 1 changed \(hiddenChanged) pixels")

        let runtime = try #require(try renderer.startSWFRuntime())
        let revealed = try Self.canvas.render(renderer)
        let revealedChanged = OffscreenRendererFixture.changedPixels(base, revealed)
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
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: false))
        try renderer.startSWFRuntime()
        let rendered = try Self.canvas.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls == 2)
        #expect(OffscreenRendererFixture.changedPixels(base, rendered) == 0)
    }

    /// Determinism survives the dynamic path: the layer moves only when
    /// something ticks it, so repeated frames of an un-ticked movie are
    /// byte-identical.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func framesAreByteIdenticalWhileTheRuntimeIsNotAdvanced() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: true))
        try renderer.startSWFRuntime()
        _ = try Self.canvas.render(renderer)
        let first = try Self.canvas.render(renderer)
        let second = try Self.canvas.render(renderer)
        #expect(first == second)
        // Advancing a one-frame movie changes nothing either, because the
        // playhead has nowhere to go.
        try renderer.advanceSWFRuntime()
        #expect(try Self.canvas.render(renderer) == first)
    }

    /// The rings are sized for the current stream plus headroom; a tick that
    /// places far more content grows them rather than dropping draws.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aGrowingDisplayListGrowsTheRingsInsteadOfDroppingDraws() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        try renderer.setSWFMovie(SWFDynamicFixture.growingScene(count: 200))
        try renderer.startSWFRuntime()
        _ = try Self.canvas.render(renderer)
        #expect(renderer.lastSWFDrawStats.drawCalls == 1)
        try renderer.advanceSWFRuntime()
        _ = try Self.canvas.render(renderer)
        let stats = renderer.lastSWFDrawStats
        #expect(stats.drawCalls == 201, "encoded \(stats.drawCalls) of 201 draws")
        #expect(stats.skippedItems == 0, "\(stats.skippedItems) draws were dropped")
    }

    /// Dropping the runtime restores the movie's static frame-1 stream, so the
    /// A/B against the static acceptance stays available.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func stoppingTheRuntimeRestoresTheStaticFrame() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        let base = try Self.canvas.render(renderer)
        try renderer.setSWFMovie(SWFDynamicFixture.scene(revealing: true))
        let hidden = try Self.canvas.render(renderer)
        try renderer.startSWFRuntime()
        #expect(try OffscreenRendererFixture
            .changedPixels(base, Self.canvas.render(renderer)) > 2000)
        try renderer.stopSWFRuntime()
        #expect(renderer.swfRuntime == nil)
        #expect(try Self.canvas.render(renderer) == hidden)
    }
}
