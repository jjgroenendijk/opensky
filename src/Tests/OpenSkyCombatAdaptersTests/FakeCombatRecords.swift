// Record stores for the combat adapters: every store empty unless a test sets it.

import Foundation
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyInventoryInterface

final class FakeCombatRecords: CombatRecordsPort {
    var factionStore: FactionStore?
    var formListStore: FormListStore?
    var gameSettings = GameSettingStore(plugins: [])
    var magicItemPluginName: String?
    var locationKeywords: KeywordStore?
    var locationStore: LocationStore?
    var magicEffectStore: MagicEffectStore?
    var questStore: QuestStore?
    var leveledScriptEdits: LeveledScriptEdits?
    var scriptFileSystem: (any GameFileSource)?
    var footstepStore: FootstepStore?
    var soundStore: SoundRecordStore?
    var actorValueBaselines: ActorValueBaselineResolver?
    var presentationRecords: PresentationRecordStore?
    var inventoryBaselines: InventoryBaselineResolver?
    var effectRecords: EffectRecordStore?
    var combatSettings = CombatSettings.synthetic
    var archerySettings = ArcherySettings.synthetic
    var difficultySettings = DifficultySettings.synthetic

    /// One race record with `flags` at DATA 0x20, the only field these adapters read.
    static func race(formID: UInt32, flags: Race.Flags) throws -> Race {
        var data = Data(count: 0x20)
        data.appendUInt32(flags.rawValue)
        data.append(Data(count: 128 - data.count))
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record("RACE", formID: formID, data: ESMFixture.field("DATA", data))
        ])
        return try Race(record: ESMFixture.firstRecord(type: "RACE", in: file), localized: false)
    }

    /// Baselines whose only record is `race`, read from `pluginName`.
    static func baselines(race: Race, pluginName: String) -> ActorValueBaselineResolver {
        ActorValueBaselineResolver(resolver: ActorValueResolver(
            templates: ActorTemplateResolver(actors: [:], leveledActors: [:]),
            races: [race.formID.rawValue: race],
            pluginName: pluginName
        ))
    }
}
