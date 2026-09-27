// Metal-gated evidence that menu mode pauses world sim while the frame still
// renders (todo 8.1.2). Drives the synchronous offscreen render path (the same
// sim-advance functions the live draw loop calls) and checks that the animation
// clock advances across frames in gameplay but holds while paused, and that a
// frame still renders in both states. Skips without a Metal 4 GPU (paravirtual
// CI); pattern from RendererUITests / RendererOffscreenTests.

import Foundation
import Metal
import MetalKit
@testable import opensky
import Testing

struct RendererMenuModeTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let width = 240
    private static let height = 160

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func gameplayAdvancesAnimationClock() throws {
        let renderer = try Self.makeRenderer()
        #expect(renderer.animationTime == 0)
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let afterFirst = renderer.animationTime
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let afterSecond = renderer.animationTime
        #expect(afterFirst > 0)
        #expect(afterSecond > afterFirst)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func menuModeFreezesAnimationClockButStillRenders() throws {
        let renderer = try Self.makeRenderer()
        renderer.worldSimPaused = true
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        // Frozen: the sim clock never advanced.
        #expect(renderer.animationTime == 0)
        // A frame still rendered at the requested size (rendering continues).
        #expect(texture.width == Self.width)
        #expect(texture.height == Self.height)
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.animationTime == 0)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func pausedFrameIsByteIdenticalThenResumeDiffers() throws {
        let renderer = try Self.makeRenderer()
        renderer.worldSimPaused = true
        let firstPaused = try Self.pixels(renderer)
        let secondPaused = try Self.pixels(renderer)
        // Sim frozen -> two paused frames match exactly.
        #expect(firstPaused == secondPaused)
        #expect(renderer.animationTime == 0)
        // Resume: the clock advances again by one frame step, no accumulated
        // jump from the paused span.
        renderer.worldSimPaused = false
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(abs(renderer.animationTime - Float(1.0 / 30)) < 1e-4)
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
    private static func pixels(_ renderer: Renderer) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(width: width, height: height)
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
}
