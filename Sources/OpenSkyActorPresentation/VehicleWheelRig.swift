// A towed cart's wheels as a rig of its own mesh nodes, so they turn as the cart
// rolls and the front axle swivels. See docs/engine/vehicles.md.

import OpenSkyBehavior
public import OpenSkyFormatsAnimation
public import OpenSkyFormatsMesh
import simd

nonisolated public struct VehicleWheelRig: Sendable {
    /// One root bone per wheel node, then the front bar, at their model-frame transforms.
    public let skeleton: HKASkeleton
    /// The height of each wheel's centre above the model's floor; 0 for the front bar.
    let radii: [Float]
    /// Which bones swivel with the front axle.
    let isFront: [Bool]
    /// The model-frame point the front axle swivels about.
    let pivot: SIMD2<Float>

    /// The node the prisoner carriage hangs its front wheels and shafts on.
    static let frontBarName = "frontbar"

    /// Nil for a model without wheel nodes.
    public init?(file: NIFFile) throws {
        let wheels = try VehicleWheels.nodes(in: file).filter { $0.transform.columns.3.z > 1 }
        guard !wheels.isEmpty else { return nil }
        let bar = try VehicleWheels.nodes(in: file, prefix: Self.frontBarName).first
        let ys = wheels.map(\.transform.columns.3.y)
        let front = (ys.max() ?? 0) - (ys.min() ?? 0) > 1 ? (ys.max() ?? 0) : .infinity
        let nodes = wheels + (bar.map { [$0] } ?? [])
        skeleton = HKASkeleton(
            name: nil,
            bones: nodes.map { HKABone(name: $0.name, lockTranslation: false) },
            parentIndices: nodes.map { _ in -1 },
            referencePose: nodes.map { HKABonePose(transform: $0.transform) }
        )
        radii = wheels.map(\.transform.columns.3.z) + (bar == nil ? [] : [0])
        isFront = wheels.map { $0.transform.columns.3.y >= front - 1 } + (bar == nil ? [] : [true])
        let barOrigin = bar?.transform.columns.3
        pivot = barOrigin.map { SIMD2($0.x, $0.y) } ?? SIMD2(0, front.isFinite ? front : 0)
    }

    /// The wheels after the cart rolled forward, along its +Y axis. Each wheel turns about
    /// the model's X axis by the arc it rolled; the front ones also swivel by `steer`.
    public func pose(_ turns: VehicleWheelTurns) -> [HKABonePose] {
        let swivel = simd_quatf(angle: -turns.steer, axis: SIMD3(0, 0, 1))
        return skeleton.referencePose.indices.map { index in
            let rest = skeleton.referencePose[index]
            let radius = radii[index]
            let front = isFront[index]
            let rolled = turns.rolled(front: front, side: rest.translation.x)
            let spin = radius > 0
                ? simd_quatf(angle: -rolled / radius, axis: SIMD3(1, 0, 0))
                : simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            guard front else {
                return HKABonePose(
                    translation: rest.translation, rotation: spin * rest.rotation, scale: rest.scale
                )
            }
            let offset = SIMD3(rest.translation.x - pivot.x, rest.translation.y - pivot.y, 0)
            let moved = swivel.act(offset) + SIMD3(pivot.x, pivot.y, rest.translation.z)
            return HKABonePose(
                translation: moved, rotation: swivel * spin * rest.rotation, scale: rest.scale
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
