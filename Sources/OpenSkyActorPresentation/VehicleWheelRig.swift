// A towed cart's wheels as a rig of its own mesh nodes, so they turn as the cart
// rolls. See docs/engine/vehicles.md.

import OpenSkyBehavior
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
            referencePose: wheels.map { HKABonePose(transform: $0.transform) }
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
}

/// One cart a cell drew with turning wheels, posed through its buffer.
nonisolated public struct CellAnimatedVehicle: Sendable {
    public let reference: UInt32
    public let rig: VehicleWheelRig
    public let pose: PlayerPoseBuffer

    public init(reference: UInt32, rig: VehicleWheelRig, pose: PlayerPoseBuffer) {
        self.reference = reference
        self.rig = rig
        self.pose = pose
    }
}
