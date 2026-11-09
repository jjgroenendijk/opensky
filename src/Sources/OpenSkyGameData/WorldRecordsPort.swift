// The record stores that adapters read from the loaded world. A port, so an adapter's
// host can pass them without the whole world data.

/// The record stores an adapter reads from the loaded world data.
nonisolated public protocol WorldRecordsPort {
    var factionStore: FactionStore? { get }
    var formListStore: FormListStore? { get }
    var gameSettings: GameSettingStore { get }
    var magicItemPluginName: String? { get }
    var locationKeywords: KeywordStore? { get }
    var locationStore: LocationStore? { get }
    var magicEffectStore: MagicEffectStore? { get }
    var questStore: QuestStore? { get }
    var leveledScriptEdits: LeveledScriptEdits? { get }
}
