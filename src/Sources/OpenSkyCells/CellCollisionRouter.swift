// Routes each collision shape into its partition or dynamic body.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldState
import simd

nonisolated extension CellSceneBuilder.CellCollisionRouter {
    /// Loads one placement's collision model and routes its solid bodies to the
    /// dynamic world or to the immutable shape list.
    nonisolated func route(
        placement: CellCollisionPlacement,
        library: NIFCollisionLibrary,
        materialTypes: MaterialTypeIndex,
        into accumulator: inout CellCollisionAccumulator
    ) {
        guard
            let model = loadCollisionModel(
                placement.modelPath, library: library, stats: &accumulator.stats
            ) else { return }
        accumulator.record(model: model)
        let solid = model.bodies.enumerated().filter(\.element.isPlayerSolid)
        let modelKey = library.canonicalKey(for: placement.modelPath)
        // Only the *simulated* bodies leave the immutable set. A model routinely
        // mixes the two — a shelf whose plank is fixed and whose contents are
        // not — and the real-data probe measured the cost of getting this wrong:
        // routing a whole model to the dynamic world because one of its bodies
        // was movable took the shelf away with it, and everything resting on the
        // shelf fell through the world.
        let simulates = Self.simulates(under: placement.motionType)
        let simulated = owner.simulatesDynamicBodies ? solid.filter { simulates($0.element) } : []
        let dynamic = dynamicPlacement(
            bodies: simulated.map(\.element),
            placement: placement,
            materialTypes: materialTypes
        )
        if let dynamic {
            accumulator.dynamicBodies.append(dynamic)
        }
        let remaining = dynamic == nil ? solid : solid.filter { !simulates($0.element) }
        for (bodyIndex, body) in remaining {
            for (shapeIndex, shape) in body.shapes.enumerated() {
                place(
                    shape: shape,
                    placement: ShapePlacement(
                        key: CellCollisionPartitionKey(modelKey, bodyIndex, shapeIndex),
                        transform: placement.transform * body.transform * shape.transform,
                        reference: placement.reference
                    ),
                    materialTypes: materialTypes,
                    into: &accumulator
                )
            }
        }
    }

    /// Which bodies simulate: the model's own choice, every body with mass after
    /// `SetMotionType(Motion_Dynamic)`, or none after `Motion_Keyframed`.
    nonisolated private static func simulates(
        under motionType: ReferenceMotionType?
    ) -> (NIFCollisionBody) -> Bool {
        switch motionType {
        case nil: { $0.dynamics.isSimulated }
        case .dynamic: { $0.dynamics.hasMass }
        case .keyframed: { _ in false }
        }
    }

    /// One placed reference's simulated body, or nil where the whole reference stays
    /// static. A model whose simulated bodies are joined by constraints stays static:
    /// without a solver, a hanging rack would fall out of the world.
    nonisolated private func dynamicPlacement(
        bodies: [NIFCollisionBody],
        placement: CellCollisionPlacement,
        materialTypes: MaterialTypeIndex
    ) -> DynamicBodyPlacement? {
        guard
            let key = placement.key,
            bodies.allSatisfy(\.constraints.isEmpty),
            let definition = DynamicBodyDefinition(
                bodies: bodies, referenceScale: placement.scale, materials: materialTypes,
                forcesSimulation: placement.motionType == .dynamic
            )
        else { return nil }
        return DynamicBodyPlacement(
            key: key,
            reference: placement.reference,
            definition: definition,
            originPosition: placement.placement.position,
            orientation: simd_quatf(MatrixMath.placement(
                position: .zero, rotation: placement.placement.rotation, scale: 1
            ))
        )
    }

    /// Places one decoded shape into the cell's shape list: its broadphase
    /// partitions through the cache, its world transform, and the MATT its
    /// Havok material resolves to. One logical shape stays one
    /// stats entry however many broadphase leaves it splits into.
    nonisolated private func place(
        shape: NIFCollisionShape,
        placement: ShapePlacement,
        materialTypes: MaterialTypeIndex,
        into accumulator: inout CellCollisionAccumulator
    ) {
        let partitioning = owner.collisionPartitionCache.partitions(
            key: placement.key,
            geometry: shape.geometry
        )
        accumulator.stats.decodeFailureCount += partitioning.failureCount
        guard !partitioning.partitions.isEmpty else { return }
        let placed = StaticCollisionShape.placed(
            reference: placement.reference,
            transform: placement.transform,
            partitions: partitioning.partitions,
            material: shape.material.flatMap(materialTypes.material(forHavokMaterial:))
        )
        accumulator.shapes.append(contentsOf: placed)
        accumulator.stats.shapeCount += 1
        accumulator.stats.triangleCount += placed.reduce(0) { $0 + $1.triangleCount }
        accumulator.stats.estimatedBytes += Self.estimatedBytes(of: shape.geometry)
    }

    nonisolated private func loadCollisionModel(
        _ path: String,
        library: NIFCollisionLibrary,
        stats: inout StaticCollisionStats
    ) -> NIFCollisionModel? {
        do {
            return try library.model(path: path)
        } catch {
            stats.loadFailureCount += 1
            let reason = String(describing: error)
            CellSceneBuilder.logger.warning(
                "collision model \(path, privacy: .public) failed: \(reason, privacy: .public)"
            )
            return nil
        }
    }

    nonisolated private static func estimatedBytes(of geometry: NIFCollisionGeometry) -> Int {
        switch geometry {
        case let .triangleSoup(vertices, indices):
            vertices.count * MemoryLayout<SIMD3<Float>>.stride
                + indices.count * MemoryLayout<UInt32>.stride
        case let .convexVertices(vertices, hullIndices):
            vertices.count * MemoryLayout<SIMD3<Float>>.stride
                + hullIndices.count * MemoryLayout<UInt32>.stride
        case .box, .sphere, .capsule:
            0
        }
    }
}
