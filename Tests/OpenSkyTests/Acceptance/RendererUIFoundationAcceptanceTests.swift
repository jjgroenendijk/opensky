// UI-shell acceptance in pixels: the localized sample changes the frame, a
// scale change moves pixels, and a paused world with the sample up repeats
// byte for byte. Skips without a Metal 4 GPU.

import Foundation
import Metal
@testable import OpenSkyMenus
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldTesting
import RenderingTesting
import simd
import TagsTesting
import Testing

@Suite(.tags(.acceptance, .gpu))
struct RendererUIFoundationAcceptanceTests {
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let canvas = OffscreenCanvas(width: 480, height: 320, shaders: .appBundle)

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func localizedSampleChangesPixelsOverBaseline() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        renderer.uiScene = .empty
        let base = try Self.canvas.render(renderer)
        renderer.uiScene = .localizedSample
        let withSample = try Self.canvas.render(renderer)
        let changed = OffscreenRendererFixture.changedPixels(base, withSample)
        // Filled panel alone covers thousands of pixels.
        #expect(changed > 2000, "localized sample changed only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func localizedSampleScaleChangesPixels() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        renderer.uiScene = .localizedSample
        renderer.uiScale = 1
        let atOne = try Self.canvas.render(renderer)
        renderer.uiScale = 2
        let atTwo = try Self.canvas.render(renderer)
        let changed = OffscreenRendererFixture.changedPixels(atOne, atTwo)
        #expect(changed > 2000, "scale change moved only \(changed) pixels")
    }

    /// Menu-mode pause with the localized sample up: repeated frames are
    /// byte-identical (frozen world + deterministic overlay) and the sim clock
    /// holds still.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func pausedLocalizedFramesRepeatByteIdentical() throws {
        let renderer = try Self.canvas.makeSessionRenderer()
        renderer.uiScene = .localizedSample
        renderer.worldSimPaused = true
        // Warm the glyph atlas so no upload happens between the compared frames.
        _ = try Self.renderPaused(renderer)
        let first = try Self.renderPaused(renderer)
        let second = try Self.renderPaused(renderer)
        #expect(first == second)
        #expect(renderer.animationTime == 0)
        #expect(renderer.lastUIDrawStats.quads > 20)
    }

    // MARK: - Helpers

    /// Renders through the sim-advancing path, the pause gate under test.
    @MainActor
    private static func renderPaused(_ renderer: Renderer) throws -> [UInt8] {
        try OffscreenRendererFixture.pixels(of: renderer.renderOffscreen(
            width: canvas.width,
            height: canvas.height
        ))
    }
}
