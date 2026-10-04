// Multi-cell scene composition (milestone 3.2): the streaming controller's
// container for built cells. Pure value logic — holds CellScenes by grid
// coordinate, recomposes them into one RenderScene via RenderScene(merging:)
// after a load/unload diff (CellGridManager). No Metal calls of its own; the
// renderer receives the composed scene through Renderer.setScene.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Built cells currently resident, keyed by exterior grid coordinate.
/// add/remove mirror the streaming controller's load/unload; composedScene
/// rebuilds the drawable union after each change.
nonisolated public struct CellSceneComposition {
    private struct DynamicDraw {
        let placingCell: CellCoordinate
        var occupiedCell: CellCoordinate?
        var scene: RenderScene
    }

    public private(set) var cells: [CellCoordinate: CellScene] = [:] {
        didSet { residentCollision = cells.values.map(\.staticCollision) }
    }
    /// Kept apart from `cells`, so a collision query walks small values and does not
    /// copy each whole `CellScene` out of the dictionary.
    private var residentCollision: [StaticCollisionSet] = []
    public private(set) var distantLOD: DistantLODScene?
    /// Per-reference draw data detached from the placing cell's bulk scene.
    /// It can therefore outlive that cell while its occupied cell is resident.
    private var dynamicDraws: [UInt32: DynamicDraw] = [:]

    public var cellCount: Int {
        cells.count
    }

    /// Coordinates currently resident — the `loaded` set fed back into
    /// CellGridManager.update.
    public var coordinates: Set<CellCoordinate> {
        Set(cells.keys)
    }

    @discardableResult
    public mutating func setCell(_ scene: CellScene, at coordinate: CellCoordinate) -> CellScene? {
        let references = Set(scene.dynamicBodies.map(\.reference.rawValue))
        dynamicDraws = dynamicDraws.filter { reference, draw in
            draw.placingCell != coordinate || references.contains(reference)
        }
        for reference in references.sorted() {
            let occupied = dynamicDraws[reference]?.occupiedCell ?? coordinate
            dynamicDraws[reference] = DynamicDraw(
                placingCell: coordinate,
                occupiedCell: occupied,
                scene: scene.renderScene.dynamicReferenceScene(reference)
            )
        }
        return cells.updateValue(scene, forKey: coordinate)
    }

    @discardableResult
    public mutating func removeCell(at coordinate: CellCoordinate) -> CellScene? {
        let removed = cells.removeValue(forKey: coordinate)
        for reference in dynamicDraws.keys.sorted() {
            guard var draw = dynamicDraws[reference] else { continue }
            if draw.occupiedCell == coordinate {
                draw.occupiedCell = nil
            }
            if draw.placingCell == coordinate, draw.occupiedCell == nil {
                dynamicDraws.removeValue(forKey: reference)
            } else {
                dynamicDraws[reference] = draw
            }
        }
        return removed
    }

    /// Moves each live dynamic draw under the exterior cell its body occupies.
    /// Returns true only when a scene recomposition is necessary.
    public mutating func setDynamicDrawOwnership(_ ownership: [UInt32: CellCoordinate]) -> Bool {
        var changed = false
        for reference in dynamicDraws.keys.sorted() {
            guard var draw = dynamicDraws[reference] else { continue }
            let occupied = ownership[reference]
            if draw.occupiedCell != occupied {
                draw.occupiedCell = occupied
                dynamicDraws[reference] = draw
                changed = true
            }
        }
        return changed
    }

    /// Union of the resident cells' draw lists via RenderScene(merging:) —
    /// cell scenes carry absolute world matrices, so no re-transform. Cells
    /// merge in (x, y) coordinate order: dictionary iteration order is
    /// nondeterministic, and the composed draw order must be stable across
    /// recompositions (deterministic frames, testable output).
    public func composedScene() -> RenderScene {
        let ordered = cells.sorted { lhs, rhs in
            (lhs.key.x, lhs.key.y) < (rhs.key.x, rhs.key.y)
        }
        var scenes: [RenderScene] = []
        for (coordinate, cell) in ordered {
            let detached = Set(dynamicDraws.compactMap { reference, draw in
                draw.placingCell == coordinate ? reference : nil
            })
            scenes.append(cell.renderScene.excludingDynamicReferences(detached))
            scenes.append(contentsOf: dynamicDraws.sorted { $0.key < $1.key }.compactMap {
                $0.value.occupiedCell == coordinate ? $0.value.scene : nil
            })
        }
        if let distantLOD {
            scenes.append(distantLOD.renderScene)
        }
        return RenderScene(merging: scenes)
    }

    @discardableResult
    public mutating func setDistantLOD(_ scene: DistantLODScene?) -> DistantLODScene? {
        let old = distantLOD
        distantLOD = scene
        return old
    }

    /// Union of the mesh + texture cache keys every resident cell uses -- the
    /// keep-set streaming hands the libraries on unload so assets no resident
    /// cell references are evicted (docs/engine/cell-streaming.md).
    public func residentAssets() -> CellAssets {
        var meshKeys: Set<String> = []
        var textureKeys: Set<String> = []
        for scene in cells.values {
            meshKeys.formUnion(scene.assets.meshKeys)
            textureKeys.formUnion(scene.assets.textureKeys)
        }
        if let distantLOD {
            meshKeys.formUnion(distantLOD.assets.meshKeys)
            textureKeys.formUnion(distantLOD.assets.textureKeys)
        }
        return CellAssets(meshKeys: meshKeys, textureKeys: textureKeys)
    }

    /// Closest teleport door across resident exterior cells, bounded by the
    /// interaction radius. Metadata is tiny + immutable; scan cost is small
    /// beside one frame's draw work.
    public func nearestDoor(to position: SIMD3<Float>, within radius: Float) -> PlacedDoor? {
        cells.values
            .flatMap(\.doors)
            .filter { simd_distance($0.position, position) <= radius }
            .min { lhs, rhs in
                simd_distance_squared(lhs.position, position)
                    < simd_distance_squared(rhs.position, position)
            }
    }

    public func interaction(reference: FormID) -> PlacedInteraction? {
        for scene in cells.values {
            if let interaction = scene.interactions[reference] {
                return interaction
            }
        }
        return nil
    }

    /// Runtime reference lookup across resident cells. Linear over a few cells, with a
    /// dictionary hit per cell.
    public func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        for scene in cells.values {
            if let entry = scene.references[key] {
                return entry
            }
        }
        return nil
    }

    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        for scene in cells.values {
            if let entry = scene.references.entry(for: formID) {
                return entry
            }
        }
        return nil
    }

    /// Which resident cell holds `key`, so a write rebuilds one cell, not all. Nil when no
    /// resident cell knows it.
    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        for scene in cells.values where scene.references[key] != nil {
            return scene.location
        }
        return nil
    }

    /// Every resident ACHR, by `ReferenceKey` in a cell and by grid across cells, so
    /// "the nearest actor" answers the same way twice. One entry per key: the first
    /// cell in grid order wins, because the worldspace persistent CELL repeats actors.
    public func actorEntries() -> [RuntimeReferenceEntry] {
        var seen = Set<ReferenceKey>()
        return cells.sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
            .flatMap { $0.value.references.sortedEntries() }
            .filter { $0.placedActor != nil && seen.insert($0.key).inserted }
    }

    /// Every resident placement, ordered by cell and then stable reference
    /// identity. Package conditions may name a disabled non-actor REFR.
    public func referenceEntries() -> [RuntimeReferenceEntry] {
        cells.sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
            .flatMap { $0.value.references.sortedEntries() }
    }

    /// Every resident cell's load summary, in `actorEntries()` grid order.
    public func actorSummaries() -> [CellLoadSummary] {
        cells.sorted { ($0.key.x, $0.key.y) < ($1.key.x, $1.key.y) }
            .map(\.value.summary)
    }

    /// Every resident container, by FormID, for picking a merchant without knowing one.
    /// Ordered by reference, so menu rows do not reshuffle when a cell streams in.
    public func containerInteractions() -> [PlacedInteraction] {
        cells.values
            .flatMap { $0.interactions.values.filter { $0.action == .search } }
            .sorted { $0.reference.rawValue < $1.reference.rawValue }
    }

    public func door(reference: FormID) -> PlacedDoor? {
        cells.values
            .flatMap(\.doors)
            .first { $0.reference == reference }
    }

    /// Ground query over resident full cells. Cell ownership uses same floor
    /// division as streaming, including negative coordinates and exact border
    /// handoff to the north/east neighbor.
    public func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample? {
        let coordinate = CellGridManager.cellCoordinate(
            for: SIMD3<Float>(position.x, position.y, 0)
        )
        return cells[coordinate]?.terrainHeightField?.sample(at: position)
    }

    /// Water height over resident full cells, by the `sampleTerrain(at:)` ownership rule.
    /// Nil where the owner is not resident or has no water.
    public func sampleWaterHeight(at position: SIMD2<Float>) -> Float? {
        let coordinate = CellGridManager.cellCoordinate(
            for: SIMD3<Float>(position.x, position.y, 0)
        )
        return cells[coordinate]?.waterHeight
    }

    /// Broadphase over resident per-cell BVHs. Cross-cell capsule queries can
    /// touch both sides of a seam; each cell remains independently evictable.
    public func collisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        residentCollision.flatMap { $0.candidates(overlapping: bounds) }
    }

    /// Trigger broadphase over resident cells, so a volume on a seam is found from either
    /// side. Cells go in (x, y) order, because script event order must be stable.
    public func triggerCandidates(overlapping bounds: ModelBounds) -> [TriggerVolume] {
        orderedCells().flatMap { $0.triggerVolumes.candidates(overlapping: bounds) }
    }

    /// Volumes the player capsule is currently inside, over every resident
    /// cell. The per-cell narrowphase runs behind each cell's own broadphase,
    /// and cell order matches `triggerCandidates(overlapping:)`.
    public func triggerVolumes(
        intersecting capsule: PlayerCapsule,
        at feetPosition: SIMD3<Float>
    ) -> [TriggerVolume] {
        orderedCells().flatMap {
            $0.triggerVolumes.volumes(intersecting: capsule, at: feetPosition)
        }
    }

    private func orderedCells() -> [CellScene] {
        cells.sorted { lhs, rhs in
            (lhs.key.x, lhs.key.y) < (rhs.key.x, rhs.key.y)
        }.map(\.value)
    }

    public func triggerStats() -> TriggerVolumeStats {
        cells.values.reduce(into: TriggerVolumeStats()) {
            $0.add($1.triggerVolumes.stats)
        }
    }

    public func collisionStats() -> StaticCollisionStats {
        cells.values.reduce(into: StaticCollisionStats()) {
            $0.add($1.staticCollision.stats)
        }
    }

    /// Union AABB over the resident cells' bounds — camera framing for a
    /// first composed scene. nil when no resident cell drew anything.
    public func composedBounds() -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var result: (min: SIMD3<Float>, max: SIMD3<Float>)?
        for bounds in cells.values.compactMap(\.bounds) {
            guard let existing = result else {
                result = bounds
                continue
            }
            result = (
                min: simd_min(existing.min, bounds.min),
                max: simd_max(existing.max, bounds.max)
            )
        }
        return result
    }
}
