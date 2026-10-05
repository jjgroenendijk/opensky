// Instanced draws through the real render loop: N placements of one model
// become one draw with `instanceCount`, each instance lands at its own screen
// position, and per-instance culling still applies. Skips without Metal 4.

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
struct RendererInstancingTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device

    private static let width = 480
    private static let height = 320

    /// Head-on from the south so the three crates project to distinct
    /// horizontal screen positions.
    private static let camera = SceneCamera(
        eye: SIMD3(0, -900, 300),
        target: SIMD3(0, 0, 32),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    private static let cratePositions: [SIMD3<Float>] = [
        SIMD3(-260, 0, 0), SIMD3(0, 0, 0), SIMD3(260, 0, 0)
    ]

    /// Three visible crates of one model (+ optionally one far outside the
    /// frustum) — all sharing one RenderMesh, so RenderScene groups them.
    private static func crateScene(
        device: MTLDevice,
        farInstance: Bool
    ) throws -> RenderScene {
        let model = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        var positions = cratePositions
        if farInstance {
            positions.append(SIMD3(1_000_000, 0, 0))
        }
        let placements = positions.map { position -> RenderPlacement in
            let transform = MatrixMath.translation(position)
            return RenderPlacement(
                model: render,
                transform: transform,
                bounds: bounds.transformed(by: transform)
            )
        }
        return RenderScene(instances: placements)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func drawsAllInstancesInOneDrawCall() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(
            device: device,
            scene: Self.crateScene(device: device, farInstance: false)
        )
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let pixels = OffscreenRendererFixture.pixels(of: texture)

        // One group, one instanced draw call, three drawn instances.
        #expect(renderer.lastDrawStats.drawCalls == 1)
        #expect(renderer.lastDrawStats.drawnInstances == 3)
        #expect(renderer.lastDrawStats.culledInstances == 0)
        // Pixel evidence: each crate's center projects to a lit pixel in
        // its own screen region, with background between the crates.
        for position in Self.cratePositions {
            let center = position + SIMD3<Float>(0, 0, 32)
            let projected = try #require(Self.project(center))
            #expect(!Self.isBackground(pixels, at: projected), "crate at \(position) missing")
        }
        let gap = try #require(Self.project(SIMD3(-130, 0, 200)))
        #expect(Self.isBackground(pixels, at: gap), "gap between crates should be background")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func cullingComposesWithInstancing() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(
            device: device,
            scene: Self.crateScene(device: device, farInstance: true)
        )
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let pixels = OffscreenRendererFixture.pixels(of: texture)

        // Far instance culled per instance; group still draws the other 3.
        #expect(renderer.lastDrawStats.drawCalls == 1)
        #expect(renderer.lastDrawStats.drawnInstances == 3)
        #expect(renderer.lastDrawStats.culledInstances == 1)
        for position in Self.cratePositions {
            let center = position + SIMD3<Float>(0, 0, 32)
            let projected = try #require(Self.project(center))
            #expect(!Self.isBackground(pixels, at: projected), "crate at \(position) missing")
        }
    }

    // MARK: - Helpers

    @MainActor
    private static func makeRenderer(
        device: MTLDevice,
        scene: RenderScene
    ) throws -> Renderer {
        try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: width, height: height,
            scene: scene,
            camera: camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
    }

    private static func project(_ world: SIMD3<Float>) -> (x: Int, y: Int)? {
        OffscreenRendererFixture.project(world, camera: camera, width: width, height: height)
    }

    private static func isBackground(_ pixels: [UInt8], at point: (x: Int, y: Int)) -> Bool {
        OffscreenRendererFixture.isBackground(pixels, at: point, width: width)
    }
}
