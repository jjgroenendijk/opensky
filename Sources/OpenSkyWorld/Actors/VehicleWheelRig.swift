// A towed cart's wheels as a rig of its own mesh nodes, so they turn as the cart
// rolls. See docs/engine/vehicles.md.

import OpenSkyFormatsAnimation
import OpenSkyFormatsMesh
import simd

nonisolated public struct VehicleWheelRig: Sendable {
    /// One root bone per wheel node, at the node's model-frame transform.
    public let skeleton: HKASkeleton
    /// The height of each wheel's centre above the model's floor.
    let radii: [Float]

    /// Nil for a model without wheel nodes.
    public init?(file: NIFFile) throws {
        let wheels = try VehicleWheels.nodes(in: file).filter { $0.transform.columns.3.z > 1 }
        guard !wheels.isEmpty else { return nil }
        skeleton = HKASkeleton(
            name: nil,
            bones: wheels.map { HKABone(name: $0.name, lockTranslation: false) },
            parentIndices: wheels.map { _ in -1 },
            referencePose: wheels.map { Self.pose(of: $0.transform) }
        )
        radii = wheels.map(\.transform.columns.3.z)
    }

    /// The wheels after the cart rolled `distance` forward, along its +Y axis. Each
    /// wheel turns about the model's X axis by the arc it rolled.
    public func pose(rolled distance: Float) -> [HKABonePose] {
        zip(skeleton.referencePose, radii).map { rest, radius in
            let spin = simd_quatf(angle: -distance / radius, axis: SIMD3(1, 0, 0))
            return HKABonePose(
                translation: rest.translation, rotation: spin * rest.rotation, scale: rest.scale
            )
        }
    }

    private static func pose(of transform: float4x4) -> HKABonePose {
        let axes = (
            SIMD3(transform.columns.0.x, transform.columns.0.y, transform.columns.0.z),
            SIMD3(transform.columns.1.x, transform.columns.1.y, transform.columns.1.z),
            SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        )
        let scale = simd_length(axes.0)
        let rotation = scale > 0
            ? simd_quatf(float3x3(axes.0 / scale, axes.1 / scale, axes.2 / scale))
            : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        return HKABonePose(
            translation: SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z),
            rotation: rotation,
            scale: SIMD3(repeating: scale)
        )
    }
}

/// One cart a cell drew with turning wheels, posed through its buffer.
nonisolated public struct CellAnimatedVehicle: Sendable {
    public let reference: UInt32
    public let rig: VehicleWheelRig
    public let pose: PlayerPoseBuffer
}
