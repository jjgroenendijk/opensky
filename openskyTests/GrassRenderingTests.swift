// Synthetic GRAS rendering gates: slope orientation, cross-cell batching,
// and runtime instance-budget accounting. No game assets.

import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct GrassRenderingTests {
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    @Test func transformAppliesYawScaleAndOptionalSlopeFit() {
        let normal = simd_normalize(SIMD3<Float>(0.4, 0.2, 1))
        let upright = Self.placement(normal: normal, flags: [])
        let fitted = Self.placement(normal: normal, flags: [.fitToSlope])
        let uprightMatrix = GrassTransform.matrix(for: upright)
        let fittedMatrix = GrassTransform.matrix(for: fitted)

        #expect(SIMD3(
            uprightMatrix.columns.2.x,
            uprightMatrix.columns.2.y,
            uprightMatrix.columns.2.z
        ) == SIMD3(0, 0, 2))
        let fittedUp = simd_normalize(SIMD3(
            fittedMatrix.columns.2.x, fittedMatrix.columns.2.y, fittedMatrix.columns.2.z
        ))
        #expect(simd_distance(fittedUp, normal) < 0.0001)
        #expect(SIMD3(
            fittedMatrix.columns.3.x, fittedMatrix.columns.3.y, fittedMatrix.columns.3.z
        ) == fitted.position)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    func mergingFoldsGrassAcrossCellsAndEvictionRemovesIt() throws {
        let device = try #require(Self.device)
        let asset = try makeAsset(device: device)
        let first = grassScene(asset: asset, positions: [SIMD3(0, 0, 0)])
        let second = grassScene(asset: asset, positions: [SIMD3(4096, 0, 0)])
        var composition = CellSceneComposition()
        composition.setCell(cell(first), at: CellCoordinate(x: 0, y: 0))
        composition.setCell(cell(second), at: CellCoordinate(x: 1, y: 0))

        let merged = composition.composedScene()
        #expect(merged.grass.count == 1)
        #expect(merged.grass[0].instances.count == 2)
        #expect(merged.instanceCount == 2)

        composition.removeCell(at: CellCoordinate(x: 0, y: 0))
        #expect(composition.composedScene().grass[0].instances.count == 1)
        composition.removeCell(at: CellCoordinate(x: 1, y: 0))
        #expect(composition.composedScene().grass.isEmpty)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func rendererEnforcesPerFrameInstanceBudget() throws {
        let device = try #require(Self.device)
        let asset = try makeAsset(device: device)
        let scene = grassScene(asset: asset, positions: [
            SIMD3(0, 0, 0), SIMD3(40, 0, 0), SIMD3(0, 40, 0)
        ])
        let camera = SceneCamera(
            eye: SIMD3(-250, -250, 150),
            target: SIMD3(20, 20, 60),
            sunDirection: SceneCamera.demo.sunDirection,
            sunColor: SceneCamera.demo.sunColor,
            ambientColor: SIMD3(repeating: 1)
        )
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: scene, camera: camera)
        renderer.shadowQuality = .off
        renderer.grassInstanceBudget = 2
        _ = try renderer.renderOffscreen(width: 320, height: 200)

        #expect(renderer.lastGrassDrawStats.sceneInstances == 3)
        #expect(renderer.lastGrassDrawStats.drawnInstances == 2)
        #expect(renderer.lastGrassDrawStats.budgetDroppedInstances == 1)
        #expect(renderer.lastGrassDrawStats.drawCalls == 1)
    }
}

extension GrassRenderingTests {
    private struct Asset {
        let model: RenderModel
        let bounds: ModelBounds
    }

    private static func placement(
        position: SIMD3<Float> = SIMD3(10, 20, 30),
        normal: SIMD3<Float> = SIMD3(0, 0, 1),
        flags: Grass.Flags = []
    ) -> GrassPlacement {
        GrassPlacement(
            grass: FormID(0x500),
            modelPath: "grass.nif",
            position: position,
            normal: normal,
            yawRadians: 0.4,
            scale: SIMD3(1, 1.5, 2),
            color: SIMD3(0.6, 0.8, 0.4),
            wavePeriod: 1,
            flags: flags
        )
    }

    private func makeAsset(device: MTLDevice) throws -> Asset {
        let positions: [SIMD3<Float>] = [
            SIMD3(-30, 0, 0), SIMD3(30, 0, 0),
            SIMD3(30, 0, 120), SIMD3(-30, 0, 120)
        ]
        let mesh = Mesh(
            name: "synthetic grass",
            transform: matrix_identity_float4x4,
            positions: positions,
            normals: [SIMD3<Float>](repeating: SIMD3(0, -1, 0), count: 4),
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)],
            colors: [],
            indices: [0, 1, 2, 0, 2, 3],
            materialSlot: 0
        )
        let material = Material(
            diffuseTexture: nil,
            normalTexture: nil,
            uvOffset: .zero,
            uvScale: SIMD2(repeating: 1),
            alpha: 1,
            glossiness: 0,
            specularColor: .zero,
            specularStrength: 0,
            doubleSided: true,
            alphaBlend: false,
            alphaTestThreshold: 0.5
        )
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: 1,
            height: 1,
            mipmapped: false
        )
        textureDescriptor.usage = .shaderRead
        let texture = try #require(device.makeTexture(descriptor: textureDescriptor))
        var white = SIMD4<UInt8>(repeating: 255)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &white,
            bytesPerRow: 4
        )
        let source = Model(meshes: [mesh], materials: [material], skippedShapeCount: 0)
        let render = try RenderModel(device: device, model: source) { _, _ in texture }
        return try Asset(
            model: render,
            bounds: #require(ModelBounds.containing(model: source))
        )
    }

    private func grassScene(asset: Asset, positions: [SIMD3<Float>]) -> RenderScene {
        RenderScene(
            instances: [],
            grass: positions.map {
                GrassRenderPlacement(
                    placement: Self.placement(position: $0),
                    model: asset.model,
                    modelBounds: asset.bounds
                )
            }
        )
    }

    private func cell(_ scene: RenderScene) -> CellScene {
        CellScene(
            renderScene: scene,
            summary: CellLoadSummary(
                cellName: "grass",
                gridX: 0,
                gridY: 0,
                totalRefCount: 0,
                drawnRefCount: 0,
                unsupportedBaseSkipCount: 0,
                markerSkipCount: 0,
                modelFailureSkipCount: 0,
                malformedRefSkipCount: 0,
                modelCount: 1,
                textureCount: 1,
                missingTextureCount: 0
            ),
            bounds: nil
        )
    }
}
