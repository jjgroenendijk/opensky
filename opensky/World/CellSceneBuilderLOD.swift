// Distant LOD bridge split from CellSceneBuilder to keep core WRLD walk dense.

nonisolated extension CellSceneBuilder {
    nonisolated func buildDistantLOD(
        worldspaceEditorID: String,
        center: CellCoordinate,
        hiddenCells: Set<CellCoordinate>
    ) throws -> DistantLODScene? {
        try distantLODBuilder?.build(
            worldspace: worldspaceEditorID,
            center: center,
            hiddenCells: hiddenCells
        )
    }
}
