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
    /// Session-stable identity of the reference, where the build retained one.
    /// A dynamic body is registered under it, because a rigid body outlives the
    /// scene it was built in and a raw FormID is not stable across plugins.
    let key: ReferenceKey?
    /// The placement's own position, euler rotation, and uniform XSCL scale,
    /// kept apart from `transform` because a simulated body integrates a pose
    /// rather than a matrix (issue #193).
    let placement: PlacedReference.Placement
    let scale: Float

    init(
        reference: FormID,
        modelPath: String,
        transform: float4x4,
        key: ReferenceKey? = nil,
        placement: PlacedReference.Placement = PlacedReference.Placement(
            position: .zero, rotation: .zero
        ),
        scale: Float = 1
    ) {
        self.reference = reference
        self.modelPath = modelPath
        self.transform = transform
        self.key = key
        self.placement = placement
        self.scale = scale
    }
}

/// The three running totals a cell's collision build carries, bundled so the
/// per-placement step can take one `inout` instead of three.
nonisolated struct CellCollisionAccumulator {
    var shapes: [StaticCollisionShape] = []
    var dynamicBodies: [DynamicBodyPlacement] = []
    var stats = StaticCollisionStats()

    /// The per-model tallies that hold whether or not any body is placed.
    mutating func record(model: NIFCollisionModel) {
        if !model.bodies.isEmpty {
            stats.collisionModelReferenceCount += 1
        }
        stats.bodyCount += model.bodies.count
        stats.filteredBodyCount += model.filteredBodyCount
        stats.unsupportedReachableBlockCount += model.unsupportedReachableBlocks.values
            .reduce(0, +)
        stats.decodeFailureCount += model.decodeFailures.count
    }
}

/// Both collision products of one cell's placements: the immutable set the
/// broadphase indexes, and the bodies the dynamic world simulates (issue #193).
nonisolated struct CellCollisionProducts {
    var collision: StaticCollisionSet
    var dynamicBodies: [DynamicBodyPlacement] = []
}

nonisolated struct CellCollisionPartitionKey: Hashable {
    let modelKey: String
    let bodyIndex: Int
    let shapeIndex: Int

    init(_ modelKey: String, _ bodyIndex: Int, _ shapeIndex: Int) {
        self.modelKey = modelKey
        self.bodyIndex = bodyIndex
        self.shapeIndex = shapeIndex
    }
}

nonisolated struct CellCollisionPartitionCache {
    private var entries: [
        CellCollisionPartitionKey: StaticCollisionPartitionResult
    ] = [:]

    mutating func partitions(
        key: CellCollisionPartitionKey,
        geometry: NIFCollisionGeometry
    ) -> StaticCollisionPartitionResult {
        if let cached = entries[key] {
            return cached
        }
        let partitions = StaticCollisionShape.partitions(for: geometry)
        entries[key] = partitions
        return partitions
    }

    mutating func evict(dropping modelKeys: Set<String>) {
        entries = entries.filter { key, _ in
            !modelKeys.contains(key.modelKey)
        }
    }

    func contains(_ key: CellCollisionPartitionKey) -> Bool {
        entries[key] != nil
    }

    var count: Int {
        entries.count
    }
}

/// Where one decoded shape lands in the world, bundled so the placement call
/// stays inside the strict parameter cap.
nonisolated struct ShapePlacement {
    let key: CellCollisionPartitionKey
    let transform: float4x4
    let reference: FormID
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

nonisolated extension CellSceneBuilder {
    /// Resolves model-bearing placements independently of render load.
    /// Collision-only NIFs stay physical when no drawable mesh uploads.
    nonisolated func resolveCollisionPlacements(
        refs: [PlacedReference],
        keys: [FormID: ReferenceKey] = [:]
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
                ),
                key: keys[ref.formID],
                placement: ref.placement,
                scale: ref.scale
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
        buildCollisionProducts(refs: refs, location: location).collision
    }

    /// The solid set and the dynamic bodies of one cell's references.
    ///
    /// - Parameter keys: FormID -> `ReferenceKey` for the same references, so a
    ///   simulated body can be registered under an identity that survives the
    ///   cell being rebuilt. A reference with no key contributes static shapes
    ///   only, which is what a build with no reference retention wants.
    nonisolated func buildCollisionProducts(
        refs: [PlacedReference],
        location: CellSceneLocation,
        keys: [FormID: ReferenceKey] = [:]
    ) -> CellCollisionProducts {
        let started = DispatchTime.now().uptimeNanoseconds
        var products = buildCollisionProducts(
            placements: resolveCollisionPlacements(refs: refs, keys: keys),
            location: location
        )
        products.collision.buildDurationMS = Double(
            DispatchTime.now().uptimeNanoseconds - started
        ) / 1_000_000
        return products
    }

    nonisolated func buildStaticCollision(
        placements: [CellCollisionPlacement],
        location: CellSceneLocation
    ) -> StaticCollisionSet {
        buildCollisionProducts(placements: placements, location: location).collision
    }

    /// Places every model-bearing reference, routing each decoded body to the
    /// immutable set or to the dynamic world.
    ///
    /// The split is the census's, not the motion byte's alone: vanilla exports
    /// most static geometry as `MO_SYS_BOX_STABILIZED` with zero mass, so
    /// `NIFRigidBodyDynamics.isSimulated` — a known simulated motion system
    /// *and* a positive finite mass — is what separates a barrel from a wall
    /// (docs/formats/nif-collision.md, dynamics census). A body that qualifies
    /// but whose reference carries no runtime key, or whose shapes yield no
    /// convex volume, falls back to being static rather than disappearing.
    nonisolated func buildCollisionProducts(
        placements: [CellCollisionPlacement],
        location: CellSceneLocation
    ) -> CellCollisionProducts {
        guard let collisionModels else {
            return CellCollisionProducts(collision: StaticCollisionSet(
                location: location,
                shapes: [],
                stats: StaticCollisionStats()
            ))
        }
        let started = DispatchTime.now().uptimeNanoseconds
        let materialTypes = materialTypeIndexBuildingIfNeeded()
        var accumulator = CellCollisionAccumulator()
        accumulator.stats.modelReferenceCount = placements.count
        for placement in placements {
            route(
                placement: placement,
                library: collisionModels,
                materialTypes: materialTypes,
                into: &accumulator
            )
        }
        let duration = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        var stats = accumulator.stats
        stats.estimatedBytes += accumulator.shapes.count
            * MemoryLayout<StaticCollisionShape>.stride
        return CellCollisionProducts(
            collision: StaticCollisionSet(
                location: location,
                shapes: accumulator.shapes,
                stats: stats,
                buildDurationMS: duration
            ),
            dynamicBodies: accumulator.dynamicBodies
        )
    }

    /// Loads one placement's collision model and routes its solid bodies to the
    /// dynamic world or to the immutable shape list.
    nonisolated private func route(
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
        let simulated = simulatesDynamicBodies
            ? solid.filter(\.element.dynamics.isSimulated)
            : []
        let dynamic = dynamicPlacement(
            bodies: simulated.map(\.element),
            placement: placement,
            materialTypes: materialTypes
        )
        if let dynamic {
            accumulator.dynamicBodies.append(dynamic)
        }
        let remaining = dynamic == nil ? solid : solid.filter { !$0.element.dynamics.isSimulated }
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
                    into: &accumulator.shapes,
                    stats: &accumulator.stats
                )
            }
        }
    }

    /// One placed reference's simulated body, or nil where the whole reference
    /// stays static.
    ///
    /// A model whose simulated bodies are bound by joints stays static
    /// wholesale. Nothing solves a constraint yet — that is item 15.6 — and the
    /// real-data probe showed what happens without this rule: a hanging rack
    /// whose joint is ignored simply falls, and keeps falling out of the world.
    /// Static is the honest answer until the joint can be honoured.
    nonisolated private func dynamicPlacement(
        bodies: [NIFCollisionBody],
        placement: CellCollisionPlacement,
        materialTypes: MaterialTypeIndex
    ) -> DynamicBodyPlacement? {
        guard
            let key = placement.key,
            bodies.allSatisfy(\.constraints.isEmpty),
            let definition = DynamicBodyDefinition(
                bodies: bodies, referenceScale: placement.scale, materials: materialTypes
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
    /// Havok material resolves to (issue #358). One logical shape stays one
    /// stats entry however many broadphase leaves it splits into.
    nonisolated private func place(
        shape: NIFCollisionShape,
        placement: ShapePlacement,
        materialTypes: MaterialTypeIndex,
        into shapes: inout [StaticCollisionShape],
        stats: inout StaticCollisionStats
    ) {
        let partitioning = collisionPartitionCache.partitions(
            key: placement.key,
            geometry: shape.geometry
        )
        stats.decodeFailureCount += partitioning.failureCount
        guard !partitioning.partitions.isEmpty else { return }
        let placed = StaticCollisionShape.placed(
            reference: placement.reference,
            transform: placement.transform,
            partitions: partitioning.partitions,
            material: shape.material.flatMap(materialTypes.material(forHavokMaterial:))
        )
        shapes.append(contentsOf: placed)
        stats.shapeCount += 1
        stats.triangleCount += placed.reduce(0) { $0 + $1.triangleCount }
        stats.estimatedBytes += Self.estimatedBytes(of: shape.geometry)
    }

    nonisolated func evictCollisionPartitions(dropping keys: Set<String>) {
        collisionPartitionCache.evict(dropping: keys)
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
