// The collision of a sequence door or a graph object, kept out of the static set so each
// moving part's shapes move with it. See docs/engine/object-animation.md#moving-collision.

import OpenSkyBehavior
import OpenSkyFormatsAnimation
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
public import OpenSkyObjectAnimation
public import OpenSkyPhysics
import OpenSkyRendering
public import simd

nonisolated public struct CellDoorCollision: Sendable {
    public let reference: FormID
    /// Where the build placed the shapes.
    public let placement: float4x4
    /// Shapes on no leaf, such as a gate's frame.
    public let fixed: [StaticCollisionShape]
    /// Each leaf's shapes, by rig bone.
    public let leaves: [[StaticCollisionShape]]
    /// The graph object's nodes, so its bone poses give the leaf deltas. Nil for a door.
    public let movingParts: MovingPartRig?

    init(
        reference: FormID, placement: float4x4, fixed: [StaticCollisionShape],
        leaves: [[StaticCollisionShape]], movingParts: MovingPartRig? = nil
    ) {
        self.reference = reference
        self.placement = placement
        self.fixed = fixed
        self.leaves = leaves
        self.movingParts = movingParts
    }

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

nonisolated extension CellSceneBuilder.CellDoorCollisionBuilder {
    /// A reference whose collision moves: its mesh, its part count, and each block's part.
    struct MovingCollisionSource {
        let ref: PlacedReference
        let modelPath: String
        let partCount: Int
        let part: (Int) -> Int?
        let movingParts: MovingPartRig?
    }

    /// Takes the shapes of each sequence door and graph object out of `set` and places
    /// their solid bodies again, grouped by the part each body's node moves with.
    func splitDoorCollision(
        _ set: StaticCollisionSet, refs: [PlacedReference]
    ) -> (fixed: StaticCollisionSet, doors: [CellDoorCollision]) {
        let sources = movingCollisionSources(in: refs)
        guard !sources.isEmpty, let library = owner.collisionModels else { return (set, []) }
        let materials = owner.modelIndex.materialTypeIndexBuildingIfNeeded()
        let fixed = StaticCollisionSet(
            location: set.location,
            shapes: set.shapes.filter { sources[$0.reference] == nil },
            stats: set.stats,
            buildDurationMS: set.buildDurationMS
        )
        let collisions = sources.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { formID in
            sources[formID].flatMap { source -> CellDoorCollision? in
                guard let model = attempt({ try library.model(path: source.modelPath) })
                else { return nil }
                let placement = MatrixMath.placement(
                    position: source.ref.placement.position,
                    rotation: source.ref.placement.rotation,
                    scale: source.ref.scale
                )
                var groups: [Int?: [StaticCollisionShape]] = [:]
                for body in model.bodies where body.isPlayerSolid && !body.dynamics.isSimulated {
                    let part = source.part(Int(body.targetBlock))
                    for shape in body.shapes {
                        groups[part, default: []] += StaticCollisionShape.placed(
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
                    leaves: (0 ..< source.partCount).map { groups[$0] ?? [] },
                    movingParts: source.movingParts
                )
            }
        }
        return (fixed, collisions)
    }

    func movingCollisionSources(
        in refs: [PlacedReference]
    ) -> [FormID: MovingCollisionSource] {
        var sources = owner.objectBuilder.animated.sequenceDoors(in: refs).mapValues { door in
            MovingCollisionSource(
                ref: door.ref, modelPath: door.modelPath,
                partCount: door.rig.skeleton.bones.count,
                part: { door.rig.leaf(ofBlock: $0) }, movingParts: nil
            )
        }
        let bases = owner.modelIndex.modelBaseIndexBuildingIfNeeded()
        for ref in refs where sources[ref.formID] == nil {
            guard
                let base = bases[ref.base.rawValue], let path = base.modelPath,
                let asset = owner.objectBuilder.animated.objectBehavior(
                    recordType: base.recordType,
                    modelPath: path
                ),
                let rig = movingPartRig(modelPath: path, boneNames: asset.skeleton.boneNames)
            else { continue }
            sources[ref.formID] = MovingCollisionSource(
                ref: ref, modelPath: path, partCount: rig.rests.count,
                part: { rig.part(ofBlock: $0) }, movingParts: rig
            )
        }
        return sources
    }

    /// The moving nodes of a graph object mesh, read once per mesh.
    func movingPartRig(modelPath: String, boneNames: [String]) -> MovingPartRig? {
        guard
            let fileSystem = owner.fileSystem,
            let key = attempt({ try owner.meshes.meshKey(for: modelPath) }) else { return nil }
        if let known = owner.caches.movingPartRigs[key] {
            return known
        }
        let rig = attempt { try NIFFile(data: fileSystem.contents(forPath: key)) }
            .flatMap { element in
                attempt { try MovingPartRig(file: element, boneNames: boneNames) }
            }
        owner.caches.movingPartRigs[key] = .some(rig)
        return rig
    }
}
