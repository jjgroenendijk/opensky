// Record stores for the Menu adapters: every store empty unless a test sets it.

import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenuAdapters
import OpenSkyPlayer

final class FakeMenuRecords: MenuRecordsPort {
    var factionStore: FactionStore?
    var formListStore: FormListStore?
    var gameSettings = GameSettingStore(plugins: [])
    var magicItemPluginName: String?
    var locationKeywords: KeywordStore?
    var locationStore: LocationStore?
    var magicEffectStore: MagicEffectStore?
    var questStore: QuestStore?
    var leveledScriptEdits: LeveledScriptEdits?
    var actorValueBaselines: ActorValueBaselineResolver?
    var speechCheckSettings = SpeechCheckSettings.fallback
    var menuRecords: MenuRecordData?
    var movementConfiguration = PlayerMovementConfiguration.synthetic
    var presentationRecords: PresentationRecordStore?
    var scriptFileSystem: (any GameFileSource)? = InMemoryFileSource()
}
