// A sequence door's collision, kept out of the static set so each leaf's shapes
// move with the leaf. See docs/engine/object-animation.md#sequence-doors.

import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyPhysics
import simd

nonisolated public struct CellDoorCollision: Sendable {
    public let reference: FormID
    /// Where the build placed the shapes.
    public let placement: float4x4
    /// Shapes on no leaf, such as a gate's frame.
    public let fixed: [StaticCollisionShape]
    /// Each leaf's shapes, by rig bone.
    public let leaves: [[StaticCollisionShape]]

    /// The shapes with each leaf moved by its model-frame delta. Nil deltas leave
    /// every leaf where the build placed it.
    public func shapes(
        leafDeltas: [float4x4]?, overlapping bounds: ModelBounds
    ) -> [StaticCollisionShape] {
        var result = fixed.filter { $0.bounds.overlaps(bounds) }
        let inverse = placement.inverse
        for (index, shapes) in leaves.enumerated() {
            guard let deltas = leafDeltas, deltas.indices.contains(index) else {
                result += shapes.filter { $0.bounds.overlaps(bounds) }
                continue
            }
            let move = placement * deltas[index] * inverse
            result += shapes.compactMap { $0.moved(by: move, overlapping: bounds) }
        }
        return result
    }
}

nonisolated extension StaticCollisionShape {
    /// This shape moved by a world-frame `delta`, or nil when it then misses `bounds`.
    func moved(by delta: float4x4, overlapping bounds: ModelBounds) -> StaticCollisionShape? {
        let moved = self.bounds.transformed(by: delta)
        guard moved.overlaps(bounds) else { return nil }
        return StaticCollisionShape(
            reference: reference,
            transform: delta * transform,
            geometry: geometry,
            bounds: moved,
            material: material
        )
    }
}

nonisolated extension CellSceneBuilder {
    /// Takes the shapes of each sequence door out of `set` and places the door's
    /// solid bodies again, grouped by the leaf each body's node moves with.
    func splitDoorCollision(
        _ set: StaticCollisionSet, refs: [PlacedReference]
    ) -> (fixed: StaticCollisionSet, doors: [CellDoorCollision]) {
        let doors = sequenceDoors(in: refs)
        guard !doors.isEmpty, let library = collisionModels else { return (set, []) }
        let materials = materialTypeIndexBuildingIfNeeded()
        let fixed = StaticCollisionSet(
            location: set.location,
            shapes: set.shapes.filter { doors[$0.reference] == nil },
            stats: set.stats,
            buildDurationMS: set.buildDurationMS
        )
        let collisions = doors.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { formID in
            doors[formID].flatMap { door -> CellDoorCollision? in
                guard let model = try? library.model(path: door.modelPath) else { return nil }
                let placement = MatrixMath.placement(
                    position: door.ref.placement.position,
                    rotation: door.ref.placement.rotation,
                    scale: door.ref.scale
                )
                var groups: [Int?: [StaticCollisionShape]] = [:]
                for body in model.bodies where body.isPlayerSolid && !body.dynamics.isSimulated {
                    let leaf = door.rig.leaf(ofBlock: Int(body.targetBlock))
                    for shape in body.shapes {
                        groups[leaf, default: []] += StaticCollisionShape.placed(
                            reference: formID,
                            transform: placement * body.transform * shape.transform,
                            geometry: shape.geometry,
                            material: shape.material.flatMap(materials.material(forHavokMaterial:))
                        )
                    }
                }
                return CellDoorCollision(
                    reference: formID,
                    placement: placement,
                    fixed: groups[Int?.none] ?? [],
                    leaves: door.rig.skeleton.bones.indices.map { groups[$0] ?? [] }
                )
            }
        }
        return (fixed, collisions)
    }
}
