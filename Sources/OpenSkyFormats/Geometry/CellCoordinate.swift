/// Integer exterior-cell coordinate for grid streaming. Distinct from
/// `Cell.Grid` (the decoded XCLC record field, which also carries the
/// force-hide-land-quad flags and belongs to one parsed plugin) — this is
/// the pure streaming-side type. `CellSceneBuilder.buildScene` still takes
/// raw `gridX`/`gridY` Int32; convert at the call site (`coordinate.x`,
/// `coordinate.y`).
nonisolated public struct CellCoordinate: Hashable, Sendable {
    public var x: Int32
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
}
