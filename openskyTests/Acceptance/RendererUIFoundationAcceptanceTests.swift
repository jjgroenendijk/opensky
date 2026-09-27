// Metal-gated pixel evidence for the M8.1 UI-shell-foundation acceptance
// (todo 8.1.4): the localized-strings sample changes the frame over the empty
// baseline, a scale change moves pixels, and a menu-mode pause with the sample
// up repeats byte-identically (frozen world, live overlay). Skips without a
// Metal 4 GPU (paravirtual CI); pattern from RendererUITests /
// RendererMenuModeTests.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererUIFoundationAcceptanceTests {
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
    func localizedSampleChangesPixelsOverBaseline() throws {
        let renderer = try Self.makeRenderer()
        renderer.uiScene = .empty
        let base = try Self.render(renderer)
        renderer.uiScene = .localizedSample
        let withSample = try Self.render(renderer)
        let changed = Self.changedPixels(base, withSample)
        // Filled panel alone covers thousands of pixels.
        #expect(changed > 2000, "localized sample changed only \(changed) pixels")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func localizedSampleScaleChangesPixels() throws {
        let renderer = try Self.makeRenderer()
        renderer.uiScene = .localizedSample
        renderer.uiScale = 1
        let atOne = try Self.render(renderer)
        renderer.uiScale = 2
        let atTwo = try Self.render(renderer)
        let changed = Self.changedPixels(atOne, atTwo)
        #expect(changed > 2000, "scale change moved only \(changed) pixels")
    }

    /// Menu-mode pause with the localized sample up: repeated frames are
    /// byte-identical (frozen world + deterministic overlay) and the sim clock
    /// holds still.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func pausedLocalizedFramesRepeatByteIdentical() throws {
        let renderer = try Self.makeRenderer()
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
        return pixels(of: texture)
    }

    /// Renders through the sim-advancing path (the pause gate under test).
    @MainActor
    private static func renderPaused(_ renderer: Renderer) throws -> [UInt8] {
        try pixels(of: renderer.renderOffscreen(width: width, height: height))
    }

    private static func pixels(of texture: MTLTexture) -> [UInt8] {
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
