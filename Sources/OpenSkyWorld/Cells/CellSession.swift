// One streaming session, split so the build queue and the main actor share no
// mutable state (docs/decisions/concurrency.md).

/// The runner owns the builder. The main actor reads only `data`.
nonisolated public struct CellSession {
    public let runner: SerialCellBuildRunner
    public let data: WorldDataStores

    public init(runner: SerialCellBuildRunner, data: WorldDataStores) {
        self.runner = runner
        self.data = data
    }
}
