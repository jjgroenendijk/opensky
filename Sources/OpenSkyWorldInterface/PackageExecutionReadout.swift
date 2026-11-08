/// What `openskycli game state packages` shows of an actor's package tree.
nonisolated public struct PackageExecutionReadout: Equatable, Sendable {
    /// The shown procedure's state, nil when no procedure runs.
    public let state: String?
    public let pathIndex: Int?
    public let pathCount: Int?
    /// Each running procedure as its kind and state, such as `travel moving`.
    public let running: [String]

    public init(state: String?, pathIndex: Int?, pathCount: Int?, running: [String]) {
        self.state = state
        self.pathIndex = pathIndex
        self.pathCount = pathCount
        self.running = running
    }
}
