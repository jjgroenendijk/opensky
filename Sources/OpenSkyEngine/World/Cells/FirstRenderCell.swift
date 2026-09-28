// Launch target: the one exterior cell OpenSky builds and renders at
// startup (todo 2.7 app wiring). Single source of truth — the AppDelegate
// scene factory and the real-data integration test both read these.
// Choice + probe data: docs/decisions/first-render-cell.md.

nonisolated enum FirstRenderCell {
    static let worldspaceEditorID = "Tamriel"
    static let gridX: Int32 = 6
    static let gridY: Int32 = -2
}
