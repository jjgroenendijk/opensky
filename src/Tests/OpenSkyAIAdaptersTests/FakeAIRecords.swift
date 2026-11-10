// Record stores for the AI adapters: every store empty unless a test sets it.

import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyGameData

final class FakeAIRecords: AIRecordsPort {
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
    var movementTypes = MovementTypeStore.empty
    var packageStore: PackageStore?
    var scriptFileSystem: (any GameFileSource)? = InMemoryFileSource()
    var shoutStore: ShoutStore?
}
