// M6.4 render gate: exact-time frames differ for a skinned actor while an
// otherwise identical static prop remains byte-identical.

import Metal
import MetalKit
@testable import opensky
import simd
import Testing

private final class SyntheticBoneAnimation: RenderAnimation {
    let mesh: RenderMesh

    init(mesh: RenderMesh) {
        self.mesh = mesh
    }

    func update(at time: Float) -> Int {
        mesh.updateSkinningPose([
            "root": MatrixMath.translation(SIMD3(time * 40, 0, 0))
        ])
    }

    func resetToBindPose() -> Int {
        mesh.updateSkinningPose(["root": matrix_identity_float4x4])
    }
}

struct ActorAnimationRenderTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func exactClipTimesChangeActorButNotStaticProp() throws {
        let device = try #require(Self.device)
        let animated = try makeScene(device: device, skinned: true)
        let staticProp = try makeScene(device: device, skinned: false)

        let actorFrames = try renderPair(
            device: device,
            scene: animated.scene,
            camera: animated.camera
        )
        let propFrames = try renderPair(
            device: device,
            scene: staticProp.scene,
            camera: staticProp.camera
        )

        #expect(actorFrames.first != actorFrames.second)
        #expect(propFrames.first == propFrames.second)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledActorAnimationRestoresBindPose() throws {
        let device = try #require(Self.device)
        let animated = try makeScene(device: device, skinned: true)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: animated.scene, camera: animated.camera)
        let moving = try pixels(renderer.renderOffscreen(
            width: 256, height: 256, animationTime: 1
        ))
        renderer.actorAnimationsEnabled = false
        let bindPose = try pixels(renderer.renderOffscreen(
            width: 256, height: 256, animationTime: 1
        ))
        #expect(moving != bindPose)
        #expect(renderer.lastAnimationUpdatedBoneCount == 1)
    }

    @MainActor
    private func renderPair(
        device: MTLDevice,
        scene: RenderScene,
        camera: SceneCamera
    ) throws -> (first: [UInt8], second: [UInt8]) {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 256, height: 256), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: scene, camera: camera)
        let first = try pixels(renderer.renderOffscreen(
            width: 256, height: 256, animationTime: 0
        ))
        let second = try pixels(renderer.renderOffscreen(
            width: 256, height: 256, animationTime: 1
        ))
        return (first, second)
    }

    private func makeScene(
        device: MTLDevice,
        skinned: Bool
    ) throws -> (scene: RenderScene, camera: SceneCamera) {
        let mesh = makeMesh(skinned: skinned)
        let texture = try makeTexture(device: device)
        let model = try RenderModel(
            device: device,
            model: Model(
                meshes: [mesh],
                materials: [makeMaterial()],
                skippedShapeCount: 0
            )
        ) { _, _ in texture }
        let bounds = ModelBounds(min: SIMD3(-80, -80, -1), max: SIMD3(80, 80, 1))
        let placement = RenderPlacement(
            model: model,
            transform: matrix_identity_float4x4,
            bounds: bounds
        )
        let animations: [any RenderAnimation] = if skinned {
            [SyntheticBoneAnimation(mesh: model.meshes[0])]
        } else {
            []
        }
        return (
            RenderScene(instances: [placement], animations: animations),
            SceneCamera.framing(bounds: (min: bounds.min, max: bounds.max))
        )
    }

    private func makeMesh(skinned: Bool) -> Mesh {
        let positions: [SIMD3<Float>] = [
            SIMD3(-30, -30, 0), SIMD3(30, -30, 0), SIMD3(0, 30, 0)
        ]
        let skinning = skinned ? MeshSkinning(
            weights: Array(repeating: SIMD4(1, 0, 0, 0), count: positions.count),
            boneIndices: Array(repeating: .zero, count: positions.count),
            bindPoseMatrices: [matrix_identity_float4x4],
            boneNames: ["root"],
            skinToBoneMatrices: [matrix_identity_float4x4]
        ) : nil
        return Mesh(
            name: skinned ? "actor" : "prop",
            transform: matrix_identity_float4x4,
            positions: positions,
            normals: Array(repeating: SIMD3(0, 0, 1), count: positions.count),
            tangents: [],
            bitangents: [],
            uvs: Array(repeating: .zero, count: positions.count),
            colors: Array(repeating: SIMD4(1, 1, 1, 1), count: positions.count),
            indices: [0, 1, 2],
            materialSlot: 0,
            skinning: skinning
        )
    }

    private func makeTexture(device: MTLDevice) throws -> MTLTexture {
        let texture = try #require(device.makeTexture(descriptor: {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: 1,
                height: 1,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            return descriptor
        }()))
        var white = SIMD4<UInt8>(repeating: 255)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &white,
            bytesPerRow: 4
        )
        return texture
    }

    private func makeMaterial() -> Material {
        Material(
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
            alphaTestThreshold: nil
        )
    }

    private func pixels(_ texture: MTLTexture) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        result.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return result
    }
}
