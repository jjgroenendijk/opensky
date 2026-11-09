// Record stores a test hands an adapter in place of the loaded world data.

public import OpenSkyGameData

/// Stores each record store, so a test sets only the ones its adapter reads.
nonisolated public final class FakeWorldRecords: WorldRecordsPort {
    public var factionStore: FactionStore?
    public var formListStore: FormListStore?
    public var gameSettings = GameSettingStore(plugins: [])
    public var magicItemPluginName: String?
    public var locationKeywords: KeywordStore?
    public var locationStore: LocationStore?
    public var magicEffectStore: MagicEffectStore?
    public var questStore: QuestStore?
    public var leveledScriptEdits: LeveledScriptEdits?
    public var actorValueBaselines: ActorValueBaselineResolver?
    public var speechCheckSettings = SpeechCheckSettings.fallback

    public init() {}
}
