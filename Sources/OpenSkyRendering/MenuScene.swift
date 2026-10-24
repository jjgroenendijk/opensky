// The menu scene: unlit effect meshes that a menu draws with its own camera, in
// place of the world. The skills menu's perk sky is one. See
// docs/rendering/menu-scene.md.

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

/// One shape's vertices and indices on the GPU.
public final class MenuSceneMesh {
    public let vertexBuffer: MTLBuffer
    public let indexBuffer: MTLBuffer
    public let indexCount: Int

    public init(shape: NIFEffectScene.Shape, device: MTLDevice) throws {
        let vertices = shape.positions.indices.map { index in
            MenuSceneVertex(
                position: SIMD4(shape.positions[index], 1),
                normal: SIMD4(shape.normals[index], 0),
                color: shape.colors[index],
                uv: shape.uvs[index]
            )
        }
        guard
            let vertexBuffer = device.makeBuffer(
                bytes: vertices,
                length: max(1, vertices.count) * MemoryLayout<MenuSceneVertex>.stride,
                options: .storageModeShared
            ),
            let indexBuffer = device.makeBuffer(
                bytes: shape.indices, length: max(1, shape.indices.count) * 2,
                options: .storageModeShared
            )
        else { throw RendererError.bufferAllocationFailed }
        vertexBuffer.label = "MenuSceneVertices"
        indexBuffer.label = "MenuSceneIndices"
        self.vertexBuffer = vertexBuffer
        self.indexBuffer = indexBuffer
        indexCount = shape.indices.count
    }
}

/// One shape to draw this frame.
public struct MenuSceneDraw {
    public let mesh: MenuSceneMesh
    public let texture: MTLTexture?
    public let palette: MTLTexture?
    /// Shape to world.
    public var transform: float4x4
    public var material: NIFEffectMaterial

    public init(
        mesh: MenuSceneMesh, texture: MTLTexture?, palette: MTLTexture?, transform: float4x4,
        material: NIFEffectMaterial
    ) {
        self.mesh = mesh
        self.texture = texture
        self.palette = palette
        self.transform = transform
        self.material = material
    }
}

/// A camera and the draws in order. The pass draws them without depth, so order
/// is what puts one shape over another, as a `BSOrderedNode` does.
public struct MenuScene {
    public var eye: SIMD3<Float>
    public var target: SIMD3<Float>
    public var up: SIMD3<Float>
    public var fovYRadians: Float
    public var draws: [MenuSceneDraw]
    /// Set, the scene draws over the world into `[0, slice]` of the depth range, with
    /// a depth test among its own shapes. Nil draws in order without depth.
    public var frontDepthSlice: Float?

    public init(
        eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>, fovYRadians: Float,
        draws: [MenuSceneDraw] = []
    ) {
        self.eye = eye
        self.target = target
        self.up = up
        self.fovYRadians = fovYRadians
        self.draws = draws
    }

    public static let nearPlane: Float = 1
    public static let farPlane: Float = 100_000

    public func viewProjection(aspectRatio: Float) -> float4x4 {
        MatrixMath.perspective(
            fovYRadians: fovYRadians, aspectRatio: aspectRatio, nearZ: Self.nearPlane,
            farZ: Self.farPlane
        ) * MatrixMath.lookAt(eye: eye, target: target, up: up)
    }

    /// Where a world point lands on the screen, 0 to 1 with y down; nil behind the camera.
    public func screenPoint(_ point: SIMD3<Float>, aspectRatio: Float) -> SIMD2<Float>? {
        let clip = viewProjection(aspectRatio: aspectRatio) * SIMD4(point, 1)
        guard clip.w > .ulpOfOne else { return nil }
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return SIMD2((ndc.x + 1) / 2, (1 - ndc.y) / 2)
    }
}
