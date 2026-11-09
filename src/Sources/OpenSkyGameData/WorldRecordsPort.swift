// The record stores that adapters read from the loaded world. A port, so an adapter's
// host can pass them without the whole world data.

/// The record stores an adapter reads from the loaded world data.
nonisolated public protocol WorldRecordsPort {
    var factionStore: FactionStore? { get }
    var magicItemPluginName: String? { get }
    var locationKeywords: KeywordStore? { get }
    var leveledScriptEdits: LeveledScriptEdits? { get }
}
