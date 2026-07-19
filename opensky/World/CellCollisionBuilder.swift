// NIF collision placement + per-cell world assembly. Input placements come
// from CellSceneBuilder's already-resolved ESM references; this layer owns no
// plugin parsing and can be tested with synthetic NIF collision models.

import Foundation
import OSLog
import simd

nonisolated struct CellCollisionPlacement {
    let reference: FormID
    let modelPath: String
    let transform: float4x4
}

nonisolated struct CellCollisionGridEntry {
    let coordinate: CellCoordinate
    let collision: StaticCollisionSet?
}

nonisolated struct CellCollisionGridResult {
    let entries: [CellCollisionGridEntry]

    var stats: StaticCollisionStats {
        entries.compactMap(\.collision).reduce(into: StaticCollisionStats()) {
            $0.add($1.stats)
        }
    }

    var voidCellCount: Int {
        entries.count(where: { $0.collision == nil })
    }

    var passesAcceptance: Bool {
        let stats = stats
        return stats.loadFailureCount == 0
            && stats.decodeFailureCount == 0
            && stats.unsupportedReachableBlockCount == 0
    }
}

nonisolated enum CellCollisionGridProbe {
    static func run(
        builder: CellSceneBuilder,
        worldspaceEditorID: String,
        center: CellCoordinate,
        radius: Int32
    ) throws -> CellCollisionGridResult {
        var entries: [CellCollisionGridEntry] = []
        for y in (center.y - radius) ... (center.y + radius) {
            for x in (center.x - radius) ... (center.x + radius) {
                let coordinate = CellCoordinate(x: x, y: y)
                do {
                    try entries.append(CellCollisionGridEntry(
                        coordinate: coordinate,
                        collision: builder.buildStaticCollision(
                            worldspaceEditorID: worldspaceEditorID,
                            gridX: x,
                            gridY: y
                        )
                    ))
                } catch let error as CellSceneError {
                    guard case .cellNotFound = error else { throw error }
                    entries.append(CellCollisionGridEntry(
                        coordinate: coordinate,
                        collision: nil
                    ))
                }
            }
        }
        return CellCollisionGridResult(entries: entries)
    }
}

extension CellSceneBuilder {
    /// Resolves model-bearing placements independently of render load.
    /// Collision-only NIFs stay physical when no drawable mesh uploads.
    nonisolated func resolveCollisionPlacements(
        refs: [PlacedReference]
    ) -> [CellCollisionPlacement] {
        guard !refs.isEmpty else { return [] }
        let statIndex = statIndexBuildingIfNeeded()
        let modelBaseIndex = modelBaseIndexBuildingIfNeeded()
        let lightIndex = lightIndexBuildingIfNeeded()
        return refs.compactMap { ref in
            guard
                lightIndex[ref.base.rawValue] == nil,
                let base = resolveBase(
                    formID: ref.base.rawValue,
                    statIndex: statIndex,
                    modelBaseIndex: modelBaseIndex
                ),
                let modelPath = base.modelPath
            else { return nil }
            return CellCollisionPlacement(
                reference: ref.formID,
                modelPath: modelPath,
                transform: MatrixMath.placement(
                    position: ref.placement.position,
                    rotation: ref.placement.rotation,
                    scale: ref.scale
                )
            )
        }
    }

    /// Collision-only exterior build for CLI stats. Same ref discovery,
    /// transforms, filters, cache as full scene build; no render upload.
    nonisolated func buildStaticCollision(
        worldspaceEditorID: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> StaticCollisionSet {
        _ = collisionModels?.drainTouchedKeys()
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let world = try worldChildrenGroup(editorID: worldspaceEditorID, localized: localized)
        guard
            let found = findCell(
                in: world.children, gridX: gridX, gridY: gridY, localized: localized
            )
        else {
            throw CellSceneError.cellNotFound(
                worldspaceEditorID: worldspaceEditorID,
                gridX: gridX,
                gridY: gridY
            )
        }
        var counts = BuildCounts()
        let localRefs = collectReferences(in: found.children, counts: &counts)
        let coordinate = CellCoordinate(x: gridX, y: gridY)
        let refs = exteriorReferences(
            local: localRefs,
            world: world.children,
            coordinate: coordinate,
            localized: localized
        )
        return buildStaticCollision(refs: refs, location: .exterior(coordinate))
    }

    nonisolated func buildStaticCollision(
        refs: [PlacedReference],
        location: CellSceneLocation
    ) -> StaticCollisionSet {
        let started = DispatchTime.now().uptimeNanoseconds
        var collision = buildStaticCollision(
            placements: resolveCollisionPlacements(refs: refs),
            location: location
        )
        collision.buildDurationMS = Double(
            DispatchTime.now().uptimeNanoseconds - started
        ) / 1_000_000
        return collision
    }

    nonisolated func buildStaticCollision(
        placements: [CellCollisionPlacement],
        location: CellSceneLocation
    ) -> StaticCollisionSet {
        guard let collisionModels else {
            return StaticCollisionSet(
                location: location,
                shapes: [],
                stats: StaticCollisionStats()
            )
        }
        let started = DispatchTime.now().uptimeNanoseconds
        var shapes: [StaticCollisionShape] = []
        var stats = StaticCollisionStats()
        stats.modelReferenceCount = placements.count
        for placement in placements {
            guard
                let model = loadCollisionModel(
                    placement.modelPath,
                    library: collisionModels,
                    stats: &stats
                ) else { continue }
            if !model.bodies.isEmpty {
                stats.collisionModelReferenceCount += 1
            }
            stats.bodyCount += model.bodies.count
            stats.filteredBodyCount += model.filteredBodyCount
            stats.unsupportedReachableBlockCount += model.unsupportedReachableBlocks.values
                .reduce(0, +)
            stats.decodeFailureCount += model.decodeFailures.count
            for body in model.bodies where body.isPlayerSolid {
                for shape in body.shapes {
                    let transform = placement.transform * body.transform * shape.transform
                    guard
                        let bounds = Self.collisionBounds(
                            geometry: shape.geometry,
                            transform: transform
                        ) else { continue }
                    let placed = StaticCollisionShape(
                        reference: placement.reference,
                        transform: transform,
                        geometry: shape.geometry,
                        bounds: bounds
                    )
                    shapes.append(placed)
                    stats.shapeCount += 1
                    stats.triangleCount += placed.triangleCount
                    stats.estimatedBytes += Self.estimatedBytes(of: shape.geometry)
                }
            }
        }
        let duration = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        stats.estimatedBytes += shapes.count * MemoryLayout<StaticCollisionShape>.stride
        return StaticCollisionSet(
            location: location,
            shapes: shapes,
            stats: stats,
            buildDurationMS: duration
        )
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
            Self.logger.warning(
                "collision model \(path, privacy: .public) failed: \(reason, privacy: .public)"
            )
            return nil
        }
    }

    nonisolated private static func collisionBounds(
        geometry: NIFCollisionGeometry,
        transform: float4x4
    ) -> ModelBounds? {
        let local: ModelBounds?
        switch geometry {
        case let .triangleSoup(vertices, _), let .convexVertices(vertices, _):
            local = ModelBounds.containing(vertices)
        case let .box(halfExtents):
            local = ModelBounds(min: -halfExtents, max: halfExtents)
        case let .sphere(radius):
            local = ModelBounds(
                min: SIMD3(repeating: -radius),
                max: SIMD3(repeating: radius)
            )
        case let .capsule(first, second, radius):
            let extent = SIMD3<Float>(repeating: radius)
            local = ModelBounds(
                min: simd_min(first, second) - extent,
                max: simd_max(first, second) + extent
            )
        }
        return local?.transformed(by: transform)
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
