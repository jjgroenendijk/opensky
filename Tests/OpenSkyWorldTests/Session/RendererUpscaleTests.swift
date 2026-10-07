// MetalFX temporal upscaling through the real render loop. Each check compares an
// upscaled frame with the native frame of the same pose: a wrong jitter or motion
// convention, or a ghost of an earlier frame, lowers the match. Skips without Metal 4.

import EngineTesting
import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
@MainActor
struct RendererUpscaleTests {
    private static let width = 480
    private static let height = 320
    private static let movingReference: UInt32 = 0x0001_0F00

    /// The demo scene plus one crate a body moves.
    private static func scene(device: MTLDevice) throws -> RenderScene {
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 24, halfDepth: 24, height: 96)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let crate = try RenderModel(device: device, model: model) { _, _ in texture }
        let transform = MatrixMath.translation(SIMD3(-60, -200, 0))
        let bounds = try #require(ModelBounds.containing(model: model))
        let moving = RenderScene(instances: [RenderPlacement(
            model: crate, transform: transform, bounds: bounds.transformed(by: transform),
            referenceFormID: movingReference
        )])
        return try RenderScene(merging: [DemoScene.build(device: device), moving])
    }

    private static func makeRenderer() throws -> Renderer {
        let device = try #require(OffscreenRendererFixture.device)
        return try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: width, height: height, scene: scene(device: device),
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
    }

    private static func frame(_ renderer: Renderer) throws -> TexturePixels {
        try TexturePixels(
            width: width, height: height,
            rgba: OffscreenRendererFixture.pixels(
                of: renderer.renderOffscreen(width: width, height: height)
            )
        )
    }

    private static func psnr(_ reference: TexturePixels, _ candidate: TexturePixels) throws
        -> Double
    {
        try TextureImageDifference.compare(
            reference: reference, candidate: candidate, normals: false
        ).rgbPSNR
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func upscaledFramesMatchTheNativeFrameStillAndPanning() throws {
        let renderer = try Self.makeRenderer()
        let start = renderer.freeFlyCamera
        var end = start
        end.yaw += 0.12
        let native = try Self.frame(renderer)
        renderer.freeFlyCamera = end
        let nativeEnd = try Self.frame(renderer)

        renderer.renderScale = RenderScale(percent: 67)
        renderer.freeFlyCamera = start
        var upscaled = native
        for _ in 0 ..< 16 {
            upscaled = try Self.frame(renderer)
        }
        #expect(renderer.upscale.sizes?.input == SIMD2(322, 214))
        #expect(renderer.upscale.sizes?.output == SIMD2(Self.width, Self.height))
        let still = try Self.psnr(native, upscaled)
        for step in 1 ... 12 {
            renderer.freeFlyCamera.yaw = start.yaw + 0.12 * Float(step) / 12
            upscaled = try Self.frame(renderer)
        }
        let pan = try Self.psnr(nativeEnd, upscaled)
        #expect(still > 31, "still frame PSNR \(still) dB")
        #expect(pan > 29.5, "panned frame PSNR \(pan) dB")
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func spatialUpscalingMatchesTheNativeFrameWithoutJitter() throws {
        let renderer = try Self.makeRenderer()
        let native = try Self.frame(renderer)
        renderer.renderScale = RenderScale(percent: 67)
        renderer.upscaler = .spatial
        let first = try Self.frame(renderer)
        let second = try Self.frame(renderer)
        #expect(renderer.upscale.unavailableReason == nil)
        #expect(renderer.upscale.sizes?.input == SIMD2(322, 214))
        #expect(renderer.upscale.targets?.motion == nil)
        // One frame is the whole input, so two frames of one pose are the same.
        #expect(try Self.psnr(first, second) > 60)
        let match = try Self.psnr(native, second)
        #expect(match > 25, "spatial frame PSNR \(match) dB")
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aMovingObjectLeavesNoGhost() throws {
        let renderer = try Self.makeRenderer()
        func move(_ step: Int) {
            renderer.dynamicInstanceDeltas[Self.movingReference] =
                MatrixMath.translation(SIMD3(Float(step) * 20, 0, 0))
        }
        move(0)
        let first = try Self.frame(renderer)
        move(16)
        let native = try Self.frame(renderer)
        let sweep = try #require(Self.changedRegion(first, native))
        func upscaledEnd(objectMotion: Bool, moving: Bool) throws -> TexturePixels {
            renderer.renderScale = RenderScale(percent: 67)
            renderer.upscale.objectMotionEnabled = objectMotion
            renderer.resetUpscaleHistory()
            var upscaled = native
            for step in 0 ... 16 {
                move(moving ? step : 16)
                upscaled = try Self.frame(renderer)
            }
            return upscaled
        }
        let reference = native.cropped(sweep)
        let still = try Self.psnr(
            reference, upscaledEnd(objectMotion: true, moving: false).cropped(sweep)
        )
        let moving = try Self.psnr(
            reference, upscaledEnd(objectMotion: true, moving: true).cropped(sweep)
        )
        let cameraOnly = try Self.psnr(
            reference, upscaledEnd(objectMotion: false, moving: true).cropped(sweep)
        )
        // A ghost trail costs far more than 2 dB. The gap left is edge softness on the
        // crate and its shadow, which lags on the static ground (captures looked at).
        #expect(moving > still - 2, "moving \(moving) dB, still \(still) dB")
        #expect(moving >= cameraOnly, "object motion \(moving) dB, camera only \(cameraOnly) dB")
    }

    /// The box around every pixel that differs between two frames.
    private static func changedRegion(_ lhs: TexturePixels, _ rhs: TexturePixels) -> PixelRegion? {
        var region: PixelRegion?
        for y in 0 ..< lhs.height {
            for x in 0 ..< lhs.width {
                let offset = (y * lhs.width + x) * 4
                let differs = (0 ..< 3).contains {
                    abs(Int(lhs.rgba[offset + $0]) - Int(rhs.rgba[offset + $0])) > 8
                }
                guard differs else { continue }
                region = region.map { $0.including(x: x, y: y) } ?? PixelRegion(x: x, y: y)
            }
        }
        return region
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aCameraCutResetsTheHistory() throws {
        let renderer = try Self.makeRenderer()
        renderer.renderScale = RenderScale(percent: 67)
        let start = renderer.freeFlyCamera
        var cut = start
        cut.position += SIMD3(2000, 0, 0)
        cut.yaw += .pi
        let fresh = try Self.makeRenderer()
        fresh.renderScale = RenderScale(percent: 67)
        fresh.freeFlyCamera = cut
        let freshCut = try Self.frame(fresh)

        for _ in 0 ..< 16 {
            _ = try Self.frame(renderer)
        }
        let resets = renderer.upscale.historyResets
        renderer.freeFlyCamera = cut
        let afterCut = try Self.frame(renderer)
        #expect(renderer.upscale.historyResets == resets + 1)
        let match = try Self.psnr(freshCut, afterCut)
        #expect(match > 40, "the frame after the cut differs from a fresh one: \(match) dB")
    }
}

private struct PixelRegion: CustomStringConvertible {
    var minX: Int
    var minY: Int
    var maxX: Int
    var maxY: Int

    init(x: Int, y: Int) {
        (minX, minY, maxX, maxY) = (x, y, x, y)
    }

    func including(x: Int, y: Int) -> Self {
        var copy = self
        copy.minX = min(minX, x)
        copy.minY = min(minY, y)
        copy.maxX = max(maxX, x)
        copy.maxY = max(maxY, y)
        return copy
    }

    var description: String {
        "\(minX),\(minY)-\(maxX),\(maxY)"
    }
}

extension TexturePixels {
    fileprivate func cropped(_ region: PixelRegion) -> TexturePixels {
        var rgba: [UInt8] = []
        for y in region.minY ... region.maxY {
            let start = (y * width + region.minX) * 4
            rgba += self.rgba[start ..< start + (region.maxX - region.minX + 1) * 4]
        }
        return TexturePixels(
            width: region.maxX - region.minX + 1, height: region.maxY - region.minY + 1, rgba: rgba
        )
    }
}
