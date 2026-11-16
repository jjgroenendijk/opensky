// A rigid shape below a billboard node turns to the camera in the static vertex shader,
// so every placement of the mesh shares one instanced draw
// (docs/formats/nif-sequences.md#billboard-nodes). Skips without Metal 4.

import Foundation
import Metal
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
import OpenSkyRenderCore
@testable import OpenSkyRendering
import OpenSkyTagsTesting
import OpenSkyWorldFixtures
import simd
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct RendererBillboardTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device
    private static let width = 480
    private static let height = 320

    /// Level with the cards and looking north, so a card at rest is seen edge-on.
    private static let camera = SceneCamera(
        eye: SIMD3(0, -900, 100),
        target: SIMD3(0, 0, 100),
        sunDirection: DemoScene.sunDirection,
        sunColor: DemoScene.sunColor,
        ambientColor: DemoScene.ambientColor
    )

    private static let cardPositions: [SIMD3<Float>] = [SIMD3(-150, 0, 100), SIMD3(150, 0, 100)]

    /// An 80-unit square card in its XY plane, facing +Z, drawn from both sides.
    private static func card(billboard: MeshBillboard?) -> Mesh {
        let positions: [SIMD3<Float>] = [[-40, -40, 0], [40, -40, 0], [40, 40, 0], [-40, 40, 0]]
        return Mesh(
            name: "Card", transform: matrix_identity_float4x4, positions: positions,
            normals: Array(repeating: SIMD3(0, 0, 1), count: 4), tangents: [], bitangents: [],
            uvs: [[0, 0], [1, 0], [1, 1], [0, 1]], colors: [],
            indices: [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2], materialSlot: 0,
            billboard: billboard
        )
    }

    private static func scene(device: any MTLDevice, billboard: MeshBillboard?) throws
        -> RenderScene
    {
        let model = Model(
            meshes: [card(billboard: billboard)], materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: model))
        return RenderScene(instances: cardPositions.map { position in
            let transform = MatrixMath.translation(position)
            return RenderPlacement(
                model: render, transform: transform, bounds: bounds.transformed(by: transform)
            )
        })
    }

    @MainActor
    private static func render(billboard: MeshBillboard?) throws
        -> (pixels: [UInt8], stats: SceneDrawStats)
    {
        let device = try #require(device)
        let renderer = try OffscreenRendererFixture.makeRenderer(
            device: device, width: width, height: height,
            scene: scene(device: device, billboard: billboard), camera: camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        let texture = try renderer.renderOffscreen(width: width, height: height)
        return (OffscreenRendererFixture.pixels(of: texture), renderer.lastDrawStats)
    }

    /// A point 25 units above each card's centre: on a turned card, off an edge-on one.
    private static func abovePoints() throws -> [(x: Int, y: Int)] {
        try cardPositions.map { position in
            try #require(OffscreenRendererFixture.project(
                position + SIMD3(0, 0, 25), camera: camera, width: width, height: height
            ))
        }
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aBillboardCardTurnsToTheEyeInOneInstancedDraw() throws {
        let billboard = MeshBillboard(
            pivot: .zero, rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), mode: 4
        )
        let frame = try Self.render(billboard: billboard)
        #expect(frame.stats.drawCalls == 1)
        #expect(frame.stats.drawnInstances == 2)
        #expect(frame.stats.billboardDrawCalls == 1)
        for point in try Self.abovePoints() {
            #expect(!OffscreenRendererFixture.isBackground(
                frame.pixels,
                at: point,
                width: Self.width
            ))
        }
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func aCardWithoutABillboardStaysEdgeOn() throws {
        let frame = try Self.render(billboard: nil)
        #expect(frame.stats.billboardDrawCalls == 0)
        for point in try Self.abovePoints() {
            #expect(OffscreenRendererFixture.isBackground(
                frame.pixels,
                at: point,
                width: Self.width
            ))
        }
    }
}
