// Multi-cell scene composition (milestone 3.2): the streaming controller's
// container for built cells. Pure value logic — holds CellScenes by grid
// coordinate, recomposes them into one RenderScene via RenderScene(merging:)
// after a load/unload diff (CellGridManager). No Metal calls of its own; the
// renderer receives the composed scene through Renderer.setScene.

import simd

/// Built cells currently resident, keyed by exterior grid coordinate.
/// add/remove mirror the streaming controller's load/unload; composedScene
/// rebuilds the drawable union after each change.
nonisolated struct CellSceneComposition {
    private(set) var cells: [CellCoordinate: CellScene] = [:]

    var cellCount: Int {
        cells.count
    }

    /// Coordinates currently resident — the `loaded` set fed back into
    /// CellGridManager.update.
    var coordinates: Set<CellCoordinate> {
        Set(cells.keys)
    }

    mutating func setCell(_ scene: CellScene, at coordinate: CellCoordinate) {
        cells[coordinate] = scene
    }

    @discardableResult
    mutating func removeCell(at coordinate: CellCoordinate) -> CellScene? {
        cells.removeValue(forKey: coordinate)
    }

    /// Union of the resident cells' draw lists via RenderScene(merging:) —
    /// cell scenes carry absolute world matrices, so no re-transform. Cells
    /// merge in (x, y) coordinate order: dictionary iteration order is
    /// nondeterministic, and the composed draw order must be stable across
    /// recompositions (deterministic frames, testable output).
    func composedScene() -> RenderScene {
        let ordered = cells.sorted { lhs, rhs in
            (lhs.key.x, lhs.key.y) < (rhs.key.x, rhs.key.y)
        }
        return RenderScene(merging: ordered.map(\.value.renderScene))
    }

    /// Union of the mesh + texture cache keys every resident cell uses -- the
    /// keep-set streaming hands the libraries on unload so assets no resident
    /// cell references are evicted (docs/engine/cell-streaming.md).
    func residentAssets() -> CellAssets {
        var meshKeys: Set<String> = []
        var textureKeys: Set<String> = []
        for scene in cells.values {
            meshKeys.formUnion(scene.assets.meshKeys)
            textureKeys.formUnion(scene.assets.textureKeys)
        }
        return CellAssets(meshKeys: meshKeys, textureKeys: textureKeys)
    }

    /// Union AABB over the resident cells' bounds — camera framing for a
    /// first composed scene. nil when no resident cell drew anything.
    func composedBounds() -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
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
