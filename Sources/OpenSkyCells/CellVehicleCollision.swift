// A towed cart's collision, kept out of the static set so it can move with the
// cart. See docs/engine/vehicles.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

nonisolated public struct CellVehicleCollision: Sendable {
    public let reference: FormID
    /// Where the build placed `shapes`.
    public let placement: float4x4
    public let shapes: [StaticCollisionShape]

    /// The shapes moved from the build's placement to `pose`.
    public func shapes(
        at pose: float4x4,
        overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        let delta = pose * placement.inverse
        return shapes.compactMap { $0.moved(by: delta, overlapping: bounds) }
    }

    /// Takes the shapes of each follower out of `set`.
    static func split(
        _ set: StaticCollisionSet, followers: [FormID: float4x4]
    ) -> (fixed: StaticCollisionSet, vehicles: [CellVehicleCollision]) {
        guard !followers.isEmpty else { return (set, []) }
        let moving = Dictionary(grouping: set.shapes.filter { followers[$0.reference] != nil }) {
            $0.reference
        }
        guard !moving.isEmpty else { return (set, []) }
        let fixed = StaticCollisionSet(
            location: set.location,
            shapes: set.shapes.filter { followers[$0.reference] == nil },
            stats: set.stats,
            buildDurationMS: set.buildDurationMS
        )
        let vehicles = moving.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { reference in
            followers[reference].map {
                CellVehicleCollision(
                    reference: reference,
                    placement: $0,
                    shapes: moving[reference] ?? []
                )
            }
        }
        return (fixed, vehicles)
    }
}
