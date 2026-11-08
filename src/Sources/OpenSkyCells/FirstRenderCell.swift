// The exterior cell OpenSky renders at startup. The app's scene factory and the
// real-data integration test both read these. See docs/decisions/first-render-cell.md.

nonisolated public enum FirstRenderCell: Sendable {
    public static let worldspaceEditorID = "Tamriel"
    public static let gridX: Int32 = 6
    public static let gridY: Int32 = -2
}
