// Metal-gated offscreen tests for the screen-space UI pass (M8.1.1). Render
// the synthetic demo scene with the UI on/off/scaled and compare pixels: the
// overlay must change the frame, an off toggle must reproduce the never-drawn
// baseline exactly, the same scene must render byte-identically (determinism),
// and a scale change must move pixels. Skips without a Metal 4 GPU (paravirtual
// CI); pattern from RendererShadowTests / RendererOffscreenTests.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererUITests {
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
    /// Fixed animation time so the 3D scene is identical across renders and any
    /// pixel delta comes only from the UI overlay.
    private static let animationTime: Float = 1

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func labSampleChangesPixelsOverBaseline() throws {
        let renderer = try Self.makeRenderer()
        renderer.uiScene = .empty
        let base = try Self.render(renderer)
        renderer.uiScene = .labSample
        let withUI = try Self.render(renderer)
        let changed = Self.changedPixels(base, withUI)
        // Filled panel alone covers thousands of pixels.
        #expect(changed > 2000, "UI overlay changed only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledUIMatchesEmptyBaselineExactly() throws {
        let renderer = try Self.makeRenderer()
        renderer.uiScene = .labSample
        renderer.uiEnabled = false
        let disabled = try Self.render(renderer)
        renderer.uiScene = .empty
        renderer.uiEnabled = true
        let empty = try Self.render(renderer)
        #expect(disabled == empty)
        #expect(renderer.lastUIDrawStats.quads == 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func sameSceneRendersByteIdentical() throws {
        let renderer = try Self.makeRenderer()
        renderer.uiScene = .labSample
        // Warm the glyph atlas so no upload happens between the compared frames.
        _ = try Self.render(renderer)
        let first = try Self.render(renderer)
        let second = try Self.render(renderer)
        #expect(first == second)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func scaleChangesPixels() throws {
        let renderer = try Self.makeRenderer()
        renderer.uiScene = .labSample
        renderer.uiScale = 1
        let atOne = try Self.render(renderer)
        renderer.uiScale = 2
        let atTwo = try Self.render(renderer)
        let changed = Self.changedPixels(atOne, atTwo)
        #expect(changed > 2000, "scale change moved only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func statsCountDrawAndGlyphs() throws {
        let renderer = try Self.makeRenderer()
        renderer.uiScene = .labSample
        _ = try Self.render(renderer)
        let stats = renderer.lastUIDrawStats
        #expect(stats.drawCalls == 1)
        #expect(stats.quads > 20)
        #expect(stats.glyphs > 10)
        #expect(stats.dropped == 0)
        #expect(stats.atlasWidth == UIGlyphAtlas.dimension)
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
