// Synthetic proving scene for the static-mesh path, built entirely in code, never game
// data (AGENTS.md). It covers opaque and alpha-tested materials, double-sided draws, UV
// tiling and REFR-style placement. Z-up, 1 unit = 1.428 cm; triangles wind
// counter-clockwise from outside (docs/decisions/coordinates.md).

import Foundation
import Metal
import OpenSkyFormatsCore
import OpenSkyShaderTypes
import simd

nonisolated public enum DemoScene: Sendable {
    // MARK: - Camera + light (consumed by the renderer's FrameUniforms)

    /// South-west of the scene, eye height well above the ground plane.
    public static let cameraEye = SIMD3<Float>(-380, -480, 280)
    public static let cameraTarget = SIMD3<Float>(0, 0, 48)

    /// Direction sunlight travels (sun in the south-west sky).
    public static let sunDirection = simd_normalize(SIMD3<Float>(0.4, 0.35, -0.85))
    public static let sunColor = SIMD3<Float>(1.0, 0.97, 0.88)
    public static let ambientColor = SIMD3<Float>(0.22, 0.24, 0.28)

    // MARK: - Scene build

    /// Builds the full demo scene: checkerboard ground, three crates (one
    /// yawed 45°, one scaled), one double-sided alpha-test cutout panel.
    public static func build(device: MTLDevice) throws -> RenderScene {
        let checker = try checkerTexture(device: device)
        let textures: [String: MTLTexture] = try [
            "demo/checker": checker,
            "demo/crate": crateTexture(device: device),
            "demo/cutout": cutoutTexture(device: device)
        ]
        let provider: TextureProvider = { key, _ in
            // Unknown keys cannot happen inside this file; fall back to the
            // checker rather than trap.
            guard let key, let texture = textures[key] else { return checker }
            return texture
        }

        let groundModel = Model(
            meshes: [planeMesh(halfSize: 512, uvRepeat: 8)],
            materials: [material(texture: "demo/checker")],
            skippedShapeCount: 0
        )
        let crateModel = Model(
            meshes: [boxMesh(halfWidth: 32, halfDepth: 32, height: 64)],
            materials: [material(texture: "demo/crate")],
            skippedShapeCount: 0
        )
        let panelModel = Model(
            meshes: [panelMesh(halfWidth: 64, height: 128)],
            materials: [material(
                texture: "demo/cutout",
                alphaTestThreshold: 0.5,
                doubleSided: true
            )],
            skippedShapeCount: 0
        )
        let ground = try RenderModel(device: device, model: groundModel, textureProvider: provider)
        let crate = try RenderModel(device: device, model: crateModel, textureProvider: provider)
        let panel = try RenderModel(device: device, model: panelModel, textureProvider: provider)
        // Model-space AABBs pushed through each placement below — the demo
        // scene carries real world bounds so frustum culling runs on the
        // no-game-data path too (same as cell scene build).
        let groundBounds = ModelBounds.containing(model: groundModel)
        let crateBounds = ModelBounds.containing(model: crateModel)
        let panelBounds = ModelBounds.containing(model: panelModel)

        // REFR-style placements (MatrixMath.placement — the exact transform
        // cell scene build will feed): identity ground, one axis-aligned
        // crate, one yawed 45°, one uniformly scaled, one cutout panel.
        var instances: [RenderPlacement] = []
        func place(_ model: RenderModel, _ bounds: ModelBounds?, _ transform: float4x4) {
            instances.append(RenderPlacement(
                model: model,
                transform: transform,
                bounds: bounds?.transformed(by: transform)
            ))
        }
        place(ground, groundBounds, matrix_identity_float4x4)
        place(crate, crateBounds, MatrixMath.placement(
            position: SIMD3(0, 0, 0), rotation: .zero, scale: 1
        ))
        place(crate, crateBounds, MatrixMath.placement(
            position: SIMD3(160, 96, 0), rotation: SIMD3(0, 0, .pi / 4), scale: 1
        ))
        place(crate, crateBounds, MatrixMath.placement(
            position: SIMD3(-144, 128, 0), rotation: .zero, scale: 1.5
        ))
        place(panel, panelBounds, MatrixMath.placement(
            position: SIMD3(-96, -96, 0), rotation: SIMD3(0, 0, .pi / 6), scale: 1
        ))
        return RenderScene(instances: instances)
    }

    // MARK: - Meshes (internal for winding/layout tests)

    private static func material(
        texture: String,
        alphaTestThreshold: Float? = nil,
        doubleSided: Bool = false
    ) -> Material {
        Material(
            diffuseTexture: texture,
            normalTexture: nil,
            uvOffset: .zero,
            uvScale: SIMD2(1, 1),
            alpha: 1,
            glossiness: 80,
            specularColor: SIMD3(1, 1, 1),
            specularStrength: 1,
            doubleSided: doubleSided,
            alphaBlend: false,
            alphaTestThreshold: alphaTestThreshold
        )
    }

    /// Ground quad at z = 0, +Z normal, UVs tiling `uvRepeat` times.
    public static func planeMesh(halfSize: Float, uvRepeat: Float) -> Mesh {
        let half = halfSize
        return Mesh(
            name: "demo-plane",
            transform: matrix_identity_float4x4,
            positions: [
                SIMD3(-half, -half, 0), SIMD3(half, -half, 0),
                SIMD3(half, half, 0), SIMD3(-half, half, 0)
            ],
            normals: Array(repeating: SIMD3(0, 0, 1), count: 4),
            tangents: [],
            bitangents: [],
            uvs: [
                SIMD2(0, uvRepeat), SIMD2(uvRepeat, uvRepeat),
                SIMD2(uvRepeat, 0), SIMD2(0, 0)
            ],
            colors: [],
            indices: [0, 1, 2, 0, 2, 3], // CCW seen from +Z (outside)
            materialSlot: 0
        )
    }

    /// Closed box sitting on z = 0, per-face normals + 0..1 UVs.
    public static func boxMesh(halfWidth: Float, halfDepth: Float, height: Float) -> Mesh {
        let dx = halfWidth
        let dy = halfDepth
        let dz = height
        // Each face: 4 verts CCW seen from outside, 2 triangles.
        let faces: [(normal: SIMD3<Float>, corners: [SIMD3<Float>])] = [
            (
                SIMD3(0, 0, 1),
                [SIMD3(-dx, -dy, dz), SIMD3(dx, -dy, dz), SIMD3(dx, dy, dz), SIMD3(-dx, dy, dz)]
            ),
            (
                SIMD3(0, 0, -1),
                [SIMD3(-dx, dy, 0), SIMD3(dx, dy, 0), SIMD3(dx, -dy, 0), SIMD3(-dx, -dy, 0)]
            ),
            (
                SIMD3(0, -1, 0),
                [SIMD3(-dx, -dy, 0), SIMD3(dx, -dy, 0), SIMD3(dx, -dy, dz), SIMD3(-dx, -dy, dz)]
            ),
            (
                SIMD3(1, 0, 0),
                [SIMD3(dx, -dy, 0), SIMD3(dx, dy, 0), SIMD3(dx, dy, dz), SIMD3(dx, -dy, dz)]
            ),
            (
                SIMD3(0, 1, 0),
                [SIMD3(dx, dy, 0), SIMD3(-dx, dy, 0), SIMD3(-dx, dy, dz), SIMD3(dx, dy, dz)]
            ),
            (
                SIMD3(-1, 0, 0),
                [SIMD3(-dx, dy, 0), SIMD3(-dx, -dy, 0), SIMD3(-dx, -dy, dz), SIMD3(-dx, dy, dz)]
            )
        ]
        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt16] = []
        for face in faces {
            let base = UInt16(positions.count)
            positions.append(contentsOf: face.corners)
            normals.append(contentsOf: Array(repeating: face.normal, count: 4))
            uvs.append(contentsOf: [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)])
            indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }
        return Mesh(
            name: "demo-box",
            transform: matrix_identity_float4x4,
            positions: positions,
            normals: normals,
            tangents: [],
            bitangents: [],
            uvs: uvs,
            colors: [],
            indices: indices,
            materialSlot: 0
        )
    }

    /// Vertical quad standing on z = 0 in the x/z plane, -Y normal (faces
    /// the demo camera). Drawn double-sided with alpha test — the foliage
    /// pipeline variant.
    public static func panelMesh(halfWidth: Float, height: Float) -> Mesh {
        let dx = halfWidth
        let dz = height
        return Mesh(
            name: "demo-panel",
            transform: matrix_identity_float4x4,
            positions: [
                SIMD3(-dx, 0, 0), SIMD3(dx, 0, 0), SIMD3(dx, 0, dz), SIMD3(-dx, 0, dz)
            ],
            normals: Array(repeating: SIMD3(0, -1, 0), count: 4),
            tangents: [],
            bitangents: [],
            uvs: [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)],
            colors: [],
            indices: [0, 1, 2, 0, 2, 3], // CCW seen from -Y (outside)
            materialSlot: 0
        )
    }

    // MARK: - Procedural textures

    private static func texture(
        device: MTLDevice,
        size: Int,
        label: String,
        pixel: (_ x: Int, _ y: Int) -> SIMD4<UInt8>
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm_srgb
        descriptor.width = size
        descriptor.height = size
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RenderMeshError.bufferAllocationFailed
        }
        texture.label = label
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                let value = pixel(x, y)
                let offset = (y * size + x) * 4
                bytes[offset] = value.x
                bytes[offset + 1] = value.y
                bytes[offset + 2] = value.z
                bytes[offset + 3] = value.w
            }
        }
        texture.replace(
            region: MTLRegionMake2D(0, 0, size, size),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: size * 4
        )
        return texture
    }

    /// Gray/white 2x2 checker per texture — tiles into a ground grid.
    private static func checkerTexture(device: MTLDevice) throws -> MTLTexture {
        try texture(device: device, size: 64, label: "demo/checker") { x, y in
            let check = (x / 32 + y / 32) % 2 == 0
            return check
                ? SIMD4(200, 200, 200, 255)
                : SIMD4(90, 90, 95, 255)
        }
    }

    /// Warm-toned crate: bordered panel with a diagonal brace — asymmetric
    /// on purpose so flipped winding/UVs are visible immediately.
    private static func crateTexture(device: MTLDevice) throws -> MTLTexture {
        try texture(device: device, size: 64, label: "demo/crate") { x, y in
            let border = x < 6 || x > 57 || y < 6 || y > 57
            let brace = abs(x - y) < 4
            if border {
                return SIMD4(96, 64, 32, 255)
            }
            if brace {
                return SIMD4(128, 90, 48, 255)
            }
            return SIMD4(180, 130, 70, 255)
        }
    }

    /// Green panel with transparent circular holes — exercises the
    /// alpha-test discard path like foliage cutouts.
    private static func cutoutTexture(device: MTLDevice) throws -> MTLTexture {
        try texture(device: device, size: 64, label: "demo/cutout") { x, y in
            let cx = Float(x % 16) - 8
            let cy = Float(y % 16) - 8
            let hole = cx * cx + cy * cy < 30
            return hole ? SIMD4(0, 0, 0, 0) : SIMD4(60, 140, 60, 255)
        }
    }
}
