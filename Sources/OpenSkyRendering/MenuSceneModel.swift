// One effect mesh ready for the menu scene: its node tree, its sequences by name,
// and a GPU mesh and textures per shape. `draws` poses it for one frame.
// See docs/rendering/menu-scene.md.

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
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
    /// turns its local +Z to the eye, with +Y kept as its up axis (Gamebryo's convention).
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

    /// nif.xml `BillboardMode`: 1, 5, and 9 turn only about the node's own +Y.
    static let aboutUpModes: Set<UInt16> = [1, 5, 9]

    /// Keeps the position and each axis's length, and turns local +Z to the eye.
    static func facing(
        _ transform: float4x4, mode: UInt16, eye: SIMD3<Float>, up: SIMD3<Float>
    ) -> float4x4 {
        let columns = [transform.columns.0, transform.columns.1, transform.columns.2]
            .map { SIMD3($0.x, $0.y, $0.z) }
        let lengths = columns.map(simd_length)
        let origin = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        let toEye = simd_normalize(eye - origin)
        let axis = aboutUpModes.contains(mode) ? simd_normalize(columns[1]) : up
        let front = aboutUpModes.contains(mode)
            ? simd_normalize(toEye - simd_dot(toEye, axis) * axis) : toEye
        let top = simd_normalize(axis - simd_dot(axis, front) * front)
        let right = simd_cross(top, front)
        guard right.x.isFinite, top.x.isFinite, front.x.isFinite else { return transform }
        return float4x4(columns: (
            SIMD4(right * lengths[0], 0), SIMD4(top * lengths[1], 0),
            SIMD4(front * lengths[2], 0), SIMD4(origin, 1)
        ))
    }
}
