// RenderScene draw-list construction tests: opaque/alpha-test grouping,
// matrix composition, residency dedup. All need a Metal device for buffer
// and texture allocation — skipped on CI without one.

import Foundation
import Metal
@testable import opensky
import simd
import Testing

struct RenderSceneTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private static func texture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.width = 1
        descriptor.height = 1
        descriptor.pixelFormat = .rgba8Unorm
        descriptor.usage = .shaderRead
        return try #require(device.makeTexture(descriptor: descriptor))
    }

    private static func mesh(slot: Int, transform: float4x4 = matrix_identity_float4x4) -> Mesh {
        Mesh(
            name: nil,
            transform: transform,
            positions: [SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)],
            normals: [],
            tangents: [],
            bitangents: [],
            uvs: [],
            colors: [],
            indices: [0, 1, 2],
            materialSlot: slot
        )
    }

    private static func material(alphaTest: Float? = nil) -> Material {
        Material(
            diffuseTexture: nil,
            normalTexture: nil,
            uvOffset: .zero,
            uvScale: SIMD2(1, 1),
            alpha: 1,
            glossiness: 80,
            specularColor: SIMD3(1, 1, 1),
            specularStrength: 1,
            doubleSided: false,
            alphaBlend: false,
            alphaTestThreshold: alphaTest
        )
    }

    private static func renderModel(device: MTLDevice) throws -> RenderModel {
        let shared = try texture(device: device)
        let model = Model(
            meshes: [mesh(slot: 1), mesh(slot: 0)],
            materials: [material(alphaTest: 0.5), material()],
            skippedShapeCount: 0
        )
        return try RenderModel(device: device, model: model) { _, _ in shared }
    }

    @Test(.enabled(if: Self.hasDevice)) func groupsOpaqueBeforeAlphaTested() throws {
        let device = try #require(Self.device)
        let model = try Self.renderModel(device: device)
        let scene = RenderScene(instances: [
            RenderPlacement(model: model, transform: matrix_identity_float4x4)
        ])

        #expect(scene.drawCount == 2)
        #expect(scene.instanceCount == 2)
        #expect(scene.opaque.count == 1)
        #expect(scene.alphaTested.count == 1)
        #expect(scene.opaque[0].material.alphaTestThreshold == nil)
        #expect(scene.alphaTested[0].material.alphaTestThreshold == 0.5)
    }

    @Test(.enabled(if: Self.hasDevice)) func composesInstanceAndLocalTransforms() throws {
        let device = try #require(Self.device)
        let local = MatrixMath.translation(SIMD3(0, 0, 5))
        let model = Model(
            meshes: [Self.mesh(slot: 0, transform: local)],
            materials: [Self.material()],
            skippedShapeCount: 0
        )
        let shared = try Self.texture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in shared }
        let instance = MatrixMath.translation(SIMD3(100, 0, 0))
        let scene = RenderScene(instances: [RenderPlacement(model: render, transform: instance)])

        let expected = instance * local
        #expect(scene.opaque[0].instances[0].modelMatrix == expected)
        #expect(scene.opaque[0].instances[0].normalMatrix == MatrixMath.normalMatrix(expected))
    }

    @Test(.enabled(if: Self.hasDevice)) func skipsMeshWithBadMaterialSlot() throws {
        let device = try #require(Self.device)
        let model = Model(
            meshes: [Self.mesh(slot: 3)],
            materials: [Self.material()],
            skippedShapeCount: 0
        )
        let shared = try Self.texture(device: device)
        let render = try RenderModel(device: device, model: model) { _, _ in shared }
        let scene = RenderScene(instances: [
            RenderPlacement(model: render, transform: matrix_identity_float4x4)
        ])
        #expect(scene.drawCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func terrainItemsCountedAndResident() throws {
        let device = try #require(Self.device)
        let mesh = try RenderMesh(device: device, mesh: Self.mesh(slot: 0))
        let weights = try #require(device.makeBuffer(
            length: 3 * 2 * MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        ))
        let base = try Self.texture(device: device)
        let layers = try [Self.texture(device: device), Self.texture(device: device)]
        let material = RenderMaterial(material: Self.material()) { _, _ in base }
        let item = TerrainDrawItem(
            mesh: mesh,
            weightsBuffer: weights,
            material: material,
            layerTextures: layers,
            modelMatrix: matrix_identity_float4x4,
            normalMatrix: matrix_identity_float4x4,
            bounds: nil
        )
        let scene = RenderScene(instances: [], terrain: [item])
        #expect(scene.drawCount == 1)
        #expect(scene.terrain[0].layerTextures.count == 2)
        // vertex + index + weights buffers, base diffuse, 2 layer textures.
        #expect(scene.residencyAllocations.count == 6)
    }

    @Test(.enabled(if: Self.hasDevice)) func mergesConcatenatingDrawListsAndResidency() throws {
        let device = try #require(Self.device)
        // Two synthetic scenes sharing one texture (openskycli render
        // --neighbors: 9 cells built off one TextureLibrary) — grid
        // composition should concat draw lists but still dedup the shared
        // allocation, same as within a single scene.
        let shared = try Self.texture(device: device)
        let model = Model(
            meshes: [Self.mesh(slot: 1), Self.mesh(slot: 0)],
            materials: [Self.material(alphaTest: 0.5), Self.material()],
            skippedShapeCount: 0
        )
        let renderA = try RenderModel(device: device, model: model) { _, _ in shared }
        let renderB = try RenderModel(device: device, model: model) { _, _ in shared }
        let sceneA = RenderScene(instances: [
            RenderPlacement(model: renderA, transform: matrix_identity_float4x4)
        ])
        let sceneB = RenderScene(instances: [
            RenderPlacement(model: renderB, transform: MatrixMath.translation(SIMD3(4096, 0, 0)))
        ])

        let merged = RenderScene(merging: [sceneA, sceneB])

        // Distinct RenderModels -> distinct meshes -> groups concatenate.
        #expect(merged.drawCount == sceneA.drawCount + sceneB.drawCount)
        #expect(merged.opaque.count == sceneA.opaque.count + sceneB.opaque.count)
        #expect(merged.alphaTested.count == sceneA.alphaTested.count + sceneB.alphaTested.count)
        #expect(merged.terrain.isEmpty)
        // 2 meshes x (vertex + index buffer) x 2 scenes + 1 shared texture = 9.
        #expect(merged.residencyAllocations.count == 9)
    }

    @Test(.enabled(if: Self.hasDevice)) func mergingFoldsSharedModelIntoOneGroup() throws {
        let device = try #require(Self.device)
        // Adjacent cells placing the same cached RenderModel (one
        // MeshLibrary) must fold into one instanced group on merge.
        let model = try Self.renderModel(device: device)
        let sceneA = RenderScene(instances: [
            RenderPlacement(model: model, transform: matrix_identity_float4x4)
        ])
        let sceneB = RenderScene(instances: [
            RenderPlacement(model: model, transform: MatrixMath.translation(SIMD3(4096, 0, 0)))
        ])

        let merged = RenderScene(merging: [sceneA, sceneB])

        #expect(merged.opaque.count == 1)
        #expect(merged.alphaTested.count == 1)
        #expect(merged.opaque[0].instances.count == 2)
        #expect(merged.alphaTested[0].instances.count == 2)
        #expect(merged.drawCount == 2)
        #expect(merged.instanceCount == 4)
    }

    @Test(.enabled(if: Self.hasDevice)) func mergingEmptyListYieldsEmptyScene() {
        let merged = RenderScene(merging: [])
        #expect(merged.drawCount == 0)
        #expect(merged.residencyAllocations.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func deduplicatesResidencyAllocations() throws {
        let device = try #require(Self.device)
        let model = try Self.renderModel(device: device)
        // Two instances of one model: buffers + shared texture counted once.
        let scene = RenderScene(instances: [
            RenderPlacement(model: model, transform: matrix_identity_float4x4),
            RenderPlacement(model: model, transform: MatrixMath.translation(SIMD3(10, 0, 0)))
        ])

        // 2 meshes -> 2 groups (1 opaque + 1 alpha-tested), 2 instances each.
        #expect(scene.drawCount == 2)
        #expect(scene.instanceCount == 4)
        // 2 meshes x (vertex + index buffer) + 1 shared texture = 5.
        #expect(scene.residencyAllocations.count == 5)
    }
}
