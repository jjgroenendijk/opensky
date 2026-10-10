// MetalFX frame interpolation through the real render loop. The frame built between two
// poses should match a frame rendered at the middle pose better than either real frame
// does. Skips without Metal 4.

import Foundation
import Metal
import OpenSkyEngineTesting
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import Testing

@Suite(.tags(.gpu))
@MainActor
struct RendererFrameInterpolationTests {
    private static let width = 480
    private static let height = 320
    private static let turn: Float = 0.08

    private static func makeRenderer() throws -> Renderer {
        let device = try #require(OffscreenRendererFixture.device)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: width, height: height, scene: DemoScene.build(device: device),
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.renderScale = RenderScale(percent: 100)
        return renderer
    }

    private static func pixels(_ texture: MTLTexture) -> TexturePixels {
        TexturePixels(
            width: width, height: height, rgba: OffscreenRendererFixture.pixels(of: texture)
        )
    }

    private static func frame(_ renderer: Renderer) throws -> TexturePixels {
        try pixels(renderer.renderOffscreen(width: width, height: height))
    }

    private static func psnr(_ reference: TexturePixels, _ candidate: TexturePixels) throws
        -> Double
    {
        try TextureImageDifference.compare(
            reference: reference, candidate: candidate, normals: false
        ).rgbPSNR
    }

    /// The upscaled frame at `yaw`, after enough frames there to settle the history.
    private static func settledFrame(yaw: Float) throws -> TexturePixels {
        let renderer = try makeRenderer()
        renderer.freeFlyCamera.yaw += yaw
        var frame = try Self.frame(renderer)
        for _ in 0 ..< 12 {
            frame = try Self.frame(renderer)
        }
        return frame
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func theBuiltFrameLiesBetweenTheTwoRealFrames() throws {
        let renderer = try Self.makeRenderer()
        try #require(renderer.upscale.resources.interpolatorUnavailableReason == nil)
        renderer.frameInterpolationEnabled = true
        var start = try Self.frame(renderer)
        for _ in 0 ..< 12 {
            start = try Self.frame(renderer)
        }
        renderer.freeFlyCamera.yaw += Self.turn
        let end = try Self.frame(renderer)
        #expect(renderer.isFrameInterpolationRunning)
        #expect(renderer.upscale.interpolation.lastFrameInterpolated)
        let built = try Self.pixels(#require(renderer.upscale.interpolation.offscreenFrame))
        let middle = try Self.settledFrame(yaw: Self.turn / 2)
        let builtMatch = try Self.psnr(middle, built)
        let startMatch = try Self.psnr(middle, start)
        let endMatch = try Self.psnr(middle, end)
        #expect(
            builtMatch > max(startMatch, endMatch),
            "built \(builtMatch) dB, start \(startMatch) dB, end \(endMatch) dB"
        )
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func itRunsOnlyWithTheTemporalUpscaler() throws {
        let renderer = try Self.makeRenderer()
        try #require(renderer.upscale.resources.interpolatorUnavailableReason == nil)
        renderer.frameInterpolationEnabled = true
        renderer.renderScale = .off
        _ = try Self.frame(renderer)
        #expect(renderer.frameInterpolationUnavailableReason?.hasPrefix("Needs") == true)
        #expect(renderer.upscale.interpolation.offscreenFrame == nil)
        renderer.renderScale = RenderScale(percent: 67)
        renderer.upscaler = .spatial
        _ = try Self.frame(renderer)
        #expect(!renderer.isFrameInterpolationRunning)
        #expect(renderer.upscale.targets?.interpolation == nil)

        renderer.upscaler = .temporal
        _ = try Self.frame(renderer)
        _ = try Self.frame(renderer)
        #expect(renderer.isFrameInterpolationRunning)
        #expect(renderer.upscale.interpolation.interpolatedFrames == 2)
        let names = renderer.renderTargetMemory().entries.map(\.name)
        #expect(names.contains("Interpolated frame"))
        renderer.frameInterpolationEnabled = false
        _ = try Self.frame(renderer)
        #expect(renderer.upscale.targets?.interpolation == nil)
        #expect(!renderer.upscale.interpolation.lastFrameInterpolated)
    }
}
