// Offscreen tests for the screen-space UI pass over the demo scene: the
// overlay changes the frame, an off toggle matches the empty baseline, frames
// repeat byte for byte, and a scale change moves pixels. Skips without Metal 4.

import Foundation
import Metal
import OpenSkyEngineTesting
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.gpu))
struct RendererUITests {
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let canvas = OffscreenCanvas(width: 480, height: 320, shaders: .packageFixture)

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func labSampleChangesPixelsOverBaseline() throws {
        let renderer = try Self.canvas.makeRenderer()
        renderer.uiScene = .empty
        let base = try Self.canvas.render(renderer)
        renderer.uiScene = .labSample
        let withUI = try Self.canvas.render(renderer)
        let changed = OffscreenRendererFixture.changedPixels(base, withUI)
        // Filled panel alone covers thousands of pixels.
        #expect(changed > 2000, "UI overlay changed only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledUIMatchesEmptyBaselineExactly() throws {
        let renderer = try Self.canvas.makeRenderer()
        renderer.uiScene = .labSample
        renderer.uiEnabled = false
        let disabled = try Self.canvas.render(renderer)
        renderer.uiScene = .empty
        renderer.uiEnabled = true
        let empty = try Self.canvas.render(renderer)
        #expect(disabled == empty)
        #expect(renderer.lastUIDrawStats.quads == 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func sameSceneRendersByteIdentical() throws {
        let renderer = try Self.canvas.makeRenderer()
        renderer.uiScene = .labSample
        // Warm the glyph atlas so no upload happens between the compared frames.
        _ = try Self.canvas.render(renderer)
        let first = try Self.canvas.render(renderer)
        let second = try Self.canvas.render(renderer)
        #expect(first == second)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func scaleChangesPixels() throws {
        let renderer = try Self.canvas.makeRenderer()
        renderer.uiScene = .labSample
        renderer.uiScale = 1
        let atOne = try Self.canvas.render(renderer)
        renderer.uiScale = 2
        let atTwo = try Self.canvas.render(renderer)
        let changed = OffscreenRendererFixture.changedPixels(atOne, atTwo)
        #expect(changed > 2000, "scale change moved only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func statsCountDrawAndGlyphs() throws {
        let renderer = try Self.canvas.makeRenderer()
        renderer.uiScene = .labSample
        _ = try Self.canvas.render(renderer)
        let stats = renderer.lastUIDrawStats
        #expect(stats.drawCalls == 1)
        #expect(stats.quads > 20)
        #expect(stats.glyphs > 10)
        #expect(stats.dropped == 0)
        #expect(stats.atlasWidth == UIGlyphAtlas.dimension)
    }
}
