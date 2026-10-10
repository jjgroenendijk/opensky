// Terrain splat blending on the GPU over a synthetic quad: a red base, a
// green ATXT layer, and layer weight 0 in the west and 1 in the east. The west
// must read red and the east green. A tilted normal map must darken the quad
// under a straight-down sun. Skips without Metal 4.

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
struct TerrainSplatRenderTests {
    private static let device = OffscreenRendererFixture.device
    private static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device

    private static let width = 320
    private static let height = 240

    /// Camera south of and above the quad center; sun straight down so the
    /// flat +Z quad gets full lambert and color channels stay comparable.
    private static let camera = SceneCamera(
        eye: SIMD3(256, -400, 600),
        target: SIMD3(256, 256, 0),
        sunDirection: SIMD3(0, 0, -1),
        sunColor: SIMD3(1, 1, 1),
        ambientColor: SIMD3(0.2, 0.2, 0.2)
    )

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func blendsLayerByVertexWeights() throws {
        let pixels = try Self.render(normal: Self.flatNormal, normalMapsEnabled: true)

        // Sample the quad's west (weight 0) and east (weight 1) interior at
        // exact projected positions — deterministic, no eyeballing.
        let west = try #require(Self.project(SIMD3(64, 256, 0)))
        let east = try #require(Self.project(SIMD3(448, 256, 0)))
        let westBGRA = Self.pixel(pixels, at: west)
        let eastBGRA = Self.pixel(pixels, at: east)

        // BGRA order: [0] blue, [1] green, [2] red.
        #expect(westBGRA[2] > westBGRA[1] + 64, "west should be base red, got \(westBGRA)")
        #expect(eastBGRA[1] > eastBGRA[2] + 64, "east should be layer green, got \(eastBGRA)")
    }

    /// A normal map that points every texel east leaves no light from a sun overhead.
    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func normalMapBendsTheLighting() throws {
        let eastNormal = SIMD4<UInt8>(255, 128, 128, 255)
        let lit = try Self.render(normal: eastNormal, normalMapsEnabled: false)
        let bent = try Self.render(normal: eastNormal, normalMapsEnabled: true)
        let west = try #require(Self.project(SIMD3(64, 256, 0)))
        let litRed = Int(Self.pixel(lit, at: west)[2])
        let bentRed = Int(Self.pixel(bent, at: west)[2])
        #expect(bentRed + 64 < litRed, "tilted normals should darken: \(bentRed) vs \(litRed)")
    }

    // MARK: - Scene assembly

    private static let flatNormal = SIMD4<UInt8>(128, 128, 255, 255)

    @MainActor
    private static func render(normal: SIMD4<UInt8>, normalMapsEnabled: Bool) throws -> [UInt8] {
        let device = try #require(Self.device)
        let scene = try Self.terrainScene(device: device, normal: normal)
        let renderer = try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: Self.width, height: Self.height,
            scene: scene,
            camera: Self.camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.terrainNormalMapsEnabled = normalMapsEnabled
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        return OffscreenRendererFixture.pixels(of: texture)
    }

    /// One 512x512 terrain quad at z = 0: red base, green layer, layer
    /// weight 0 on west vertices and 1 on east vertices.
    private static func terrainScene(
        device: MTLDevice,
        normal: SIMD4<UInt8>
    ) throws -> RenderScene {
        let mesh = Mesh(
            name: "splat-quad",
            transform: matrix_identity_float4x4,
            positions: [
                SIMD3(0, 0, 0), SIMD3(512, 0, 0), SIMD3(512, 512, 0), SIMD3(0, 512, 0)
            ],
            normals: Array(repeating: SIMD3(0, 0, 1), count: 4),
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)],
            colors: [],
            indices: [0, 1, 2, 0, 2, 3], // CCW seen from +Z
            materialSlot: 0
        )
        let renderMesh = try RenderMesh(device: device, mesh: mesh)

        // Lane 0 = the single layer: east vertices (1, 2) fully painted.
        let weights: [SIMD4<Float>] = [
            .zero, .zero, // v0 west
            SIMD4(1, 0, 0, 0), .zero, // v1 east
            SIMD4(1, 0, 0, 0), .zero, // v2 east
            .zero, .zero // v3 west
        ]
        let weightsBuffer = try #require(device.makeBuffer(
            bytes: weights,
            length: weights.count * MemoryLayout<SIMD4<Float>>.stride,
            options: .storageModeShared
        ))

        let base = try solidTexture(device: device, rgba: SIMD4(255, 0, 0, 255), label: "base-red")
        let layer = try solidTexture(
            device: device, rgba: SIMD4(0, 255, 0, 255), label: "layer-green"
        )
        let normalMap = try solidTexture(
            device: device, rgba: normal, label: "normal", pixelFormat: .rgba8Unorm
        )
        let material = RenderMaterial(
            material: .fallback,
            textureProvider: { _, _ in base }
        )
        let item = TerrainDrawItem(
            mesh: renderMesh,
            weightsBuffer: weightsBuffer,
            material: material,
            layerTextures: [layer],
            normals: TerrainNormalMaps(base: normalMap, layers: [normalMap], resolvedCount: 2),
            modelMatrix: matrix_identity_float4x4,
            normalMatrix: matrix_identity_float4x4,
            bounds: nil
        )
        return RenderScene(instances: [], terrain: [item])
    }

    private static func solidTexture(
        device: MTLDevice,
        rgba: SIMD4<UInt8>,
        label: String,
        pixelFormat: MTLPixelFormat = .rgba8Unorm_srgb
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = pixelFormat
        descriptor.width = 4
        descriptor.height = 4
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        texture.label = label
        var bytes = [UInt8]()
        for _ in 0 ..< 16 {
            bytes.append(contentsOf: [rgba.x, rgba.y, rgba.z, rgba.w])
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, 4, 4),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: 4 * 4
        )
        return texture
    }

    // MARK: - Projection helper

    private static func project(_ world: SIMD3<Float>) -> (x: Int, y: Int)? {
        OffscreenRendererFixture.project(world, camera: camera, width: width, height: height)
    }

    private static func pixel(_ pixels: [UInt8], at point: (x: Int, y: Int)) -> [UInt8] {
        let offset = (point.y * width + point.x) * 4
        return Array(pixels[offset ..< offset + 4])
    }
}
