// One effect mesh ready for the menu scene: its node tree, its sequences by name,
// and a GPU mesh and textures per shape. `draws` poses it for one frame.
// See docs/rendering/menu-scene.md.

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyRenderResources
import simd

public final class MenuSceneModel {
    public let scene: NIFEffectScene
    public let sequences: [String: NIFSequence]
    let meshes: [MenuSceneMesh]
    let textures: [MTLTexture?]
    let palettes: [MTLTexture?]

    public init(file: NIFFile, device: MTLDevice, textures provider: TextureProvider) throws {
        scene = try NIFEffectScene(file: file)
        sequences = try Dictionary(
            file.sequences().map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        meshes = try scene.shapes.map { try MenuSceneMesh(shape: $0, device: device) }
        textures = scene.shapes.map { shape in
            shape.material.sourceTexture.map { provider($0, .color) }
        }
        palettes = scene.shapes.map { shape in
            shape.material.shading.paletteTexture.map { provider($0, .color) }
        }
    }

    /// The sequence by name, compared without case.
    public func sequence(_ name: String) -> NIFSequence? {
        sequences[name.lowercased()]
    }

    /// A node's position in the mesh with the sequences applied.
    public func nodePosition(_ name: String, playing: [NIFEffectPose.Playing]) -> SIMD3<Float>? {
        guard let node = scene.node(named: name) else { return nil }
        let pose = NIFEffectPose(scene: scene, playing: playing)
        let transform = scene.modelTransform(of: node) { pose.locals[$0] }
        return SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
    }

    /// The visible shapes posed by `playing`, placed by `placement`. A billboard node
    /// turns to the eye by its mode (`NIFBillboard`).
    public func draws(
        playing: [NIFEffectPose.Playing], placement: float4x4, eye: SIMD3<Float>,
        up: SIMD3<Float>
    ) -> [MenuSceneDraw] {
        draws(
            pose: NIFEffectPose(scene: scene, playing: playing), placement: placement, eye: eye,
            up: up
        )
    }

    /// The visible shapes of a pose built by the caller, such as one with a node it moves.
    public func draws(
        pose: NIFEffectPose, placement: float4x4, eye: SIMD3<Float>, up: SIMD3<Float>
    ) -> [MenuSceneDraw] {
        pose.shapes(of: scene).compactMap { state in
            guard state.isVisible else { return nil }
            var transform = placement * state.transform
            if let billboard = state.billboard {
                let node = Self.facing(
                    placement * billboard.node, mode: billboard.mode, eye: eye, up: up
                )
                transform = node * billboard.below
            }
            return MenuSceneDraw(
                mesh: meshes[state.shape], texture: textures[state.shape],
                palette: palettes[state.shape], transform: transform, material: state.material
            )
        }
    }

    /// Keeps the position and each axis's length, and turns the node by its billboard mode.
    static func facing(
        _ transform: float4x4, mode: UInt16, eye: SIMD3<Float>, up: SIMD3<Float>
    ) -> float4x4 {
        let columns = [transform.columns.0, transform.columns.1, transform.columns.2]
            .map { SIMD3($0.x, $0.y, $0.z) }
        let lengths = columns.map(simd_length)
        guard lengths.allSatisfy({ $0 > 0 }) else { return transform }
        let origin = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let authored = simd_quatf(simd_float3x3(
            columns[0] / lengths[0], columns[1] / lengths[1], columns[2] / lengths[2]
        ))
        guard let turned = NIFBillboard.rotation(
            mode: mode, rotation: authored.normalized, origin: origin,
            viewer: NIFBillboard.Viewer(eye: eye, forward: nil, up: up)
        ) else { return transform }
        let basis = simd_float3x3(turned)
        return float4x4(columns: (
            SIMD4(basis.columns.0 * lengths[0], 0), SIMD4(basis.columns.1 * lengths[1], 0),
            SIMD4(basis.columns.2 * lengths[2], 0), SIMD4(origin, 1)
        ))
    }
}
