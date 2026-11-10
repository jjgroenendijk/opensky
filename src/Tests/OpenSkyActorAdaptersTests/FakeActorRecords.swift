// Record stores for the actor adapters: every store empty unless a test sets it.

import OpenSkyActorAdapters
import OpenSkyAIPackages
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyWorldInterface

final class FakeActorRecords: ActorRecordsPort {
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
    var dragonFlightSettings = DragonFlightSettings()
    var idleStore: IdleStore?
    var mountMovementConfiguration = PlayerMovementConfiguration.synthetic
    var packageStore: PackageStore?
    var scriptFileSystem: (any GameFileSource)?
}
