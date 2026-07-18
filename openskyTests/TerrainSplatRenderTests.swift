// Offscreen render of the terrain splat pipeline over a fully synthetic
// scene: one terrain quad, solid red base diffuse, solid green ATXT layer,
// layer weight 0 on the west edge and 1 on the east edge. Pixel-level check
// that VTXT-driven blending actually happens on the GPU: west reads red
// (base only), east reads green (layer fully blended in). Skips without a
// Metal 4 device (paravirtual CI), pattern from RendererOffscreenTests.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct TerrainSplatRenderTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

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
        let device = try #require(Self.device)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false

        let scene = try Self.terrainScene(device: device)
        let renderer = try Renderer(view: view, scene: scene, camera: Self.camera)
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)

        var pixels = [UInt8](repeating: 0, count: Self.width * Self.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: Self.width * 4,
                from: MTLRegionMake2D(0, 0, Self.width, Self.height),
                mipmapLevel: 0
            )
        }

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

    // MARK: - Scene assembly

    /// One 512x512 terrain quad at z = 0: red base, green layer, layer
    /// weight 0 on west vertices and 1 on east vertices.
    private static func terrainScene(device: MTLDevice) throws -> RenderScene {
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
        let material = RenderMaterial(
            material: .fallback,
            textureProvider: { _, _ in base }
        )
        let item = TerrainDrawItem(
            mesh: renderMesh,
            weightsBuffer: weightsBuffer,
            material: material,
            layerTextures: [layer],
            modelMatrix: matrix_identity_float4x4,
            normalMatrix: matrix_identity_float4x4
        )
        return RenderScene(instances: [], terrain: [item])
    }

    private static func solidTexture(
        device: MTLDevice,
        rgba: SIMD4<UInt8>,
        label: String
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm_srgb
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

    /// Projects a world point through the same view + projection the
    /// offscreen render uses; nil when it lands off screen.
    private static func project(_ world: SIMD3<Float>) -> (x: Int, y: Int)? {
        let viewMatrix = FreeFlyCamera(framing: camera).viewMatrix()
        let projection = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: Float(width) / Float(height),
            nearZ: Renderer.nearPlane,
            farZ: Renderer.farPlane
        )
        let clip = projection * viewMatrix * SIMD4(world, 1)
        guard clip.w > 0 else { return nil }
        let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
        guard abs(ndc.x) < 1, abs(ndc.y) < 1 else { return nil }
        let x = Int((ndc.x + 1) / 2 * Float(width))
        let y = Int((1 - ndc.y) / 2 * Float(height))
        return (x, y)
    }

    private static func pixel(_ pixels: [UInt8], at point: (x: Int, y: Int)) -> [UInt8] {
        let offset = (point.y * width + point.x) * 4
        return Array(pixels[offset ..< offset + 4])
    }
}
