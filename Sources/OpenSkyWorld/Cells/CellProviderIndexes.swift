// Complete index set backing the streamed-cell provider. Keeping this
// assembly outside AppDelegate makes additions testable without app startup.
// `CellProviderIndexes+Load.swift` builds it off the main actor, in stages.

import Metal
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorldState

nonisolated public struct CellProviderIndexes {
    /// The load-order magic stores (MGEF, SPEL, SCRL, EQUP, ENCH), decoded off one
    /// shared `RecordIndex` so the plugins are walked once.
    struct MagicIndexes: Sendable {
        let effects: MagicEffectStore
        let spells: SpellStore
        let equipSlots: EquipSlotStore
        let enchantments: EnchantmentStore
        /// PERK and AVIF ride the same index: perk effects join against the SPEL
        /// store, and the perk trees hang off the AVIF records.
        let perks: PerkStore
        let actorValues: ActorValueInformationStore

        init(plugins: [(name: String, file: ESMFile)]) {
            let index = RecordIndex(
                plugins: plugins,
                recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "ENCH", "PERK", "AVIF"]
            )
            let effects = MagicEffectStore(index: index)
            self.effects = effects
            spells = SpellStore(index: index, effects: effects)
            equipSlots = EquipSlotStore(index: index)
            enchantments = EnchantmentStore(index: index, effects: effects)
            perks = PerkStore(index: index, spells: spells)
            actorValues = ActorValueInformationStore(index: index)
        }
    }

    /// Every GMST-derived tuning, resolved off one load of the settings table.
    struct SettingIndexes: Sendable {
        let movement: PlayerMovementConfiguration
        let barter: BarterPricing
        let combat: CombatSettings
        let difficulty: DifficultySettings
        let archery: ArcherySettings
        let detection: DetectionSettings
        let skillAdvancement: SkillAdvancementSettings
        let characterLevel: CharacterLevelSettings
        let level: ActorValueLevelSettings
        /// Kept for `LockTrapData`, which reads the lockpicking settings off it.
        let store: GameSettingStore

        init(plugins: [(name: String, file: ESMFile)]) {
            let settings = GameSettingStore(plugins: plugins)
            movement = PlayerMovementConfiguration.resolve(
                store: settings,
                movementTypes: MovementTypeStore(plugins: plugins)
            )
            barter = BarterPricing.resolve(store: settings)
            combat = CombatSettings.resolve(store: settings)
            difficulty = DifficultySettings.resolve(store: settings)
            archery = ArcherySettings.resolve(store: settings)
            detection = DetectionSettings.resolve(store: settings)
            skillAdvancement = SkillAdvancementSettings.resolve(store: settings)
            characterLevel = CharacterLevelSettings.resolve(store: settings)
            level = ActorValueLevelSettings.resolve(store: settings)
            store = settings
        }
    }

    /// The audio and weather stores. They are classes without `Sendable`, so
    /// the loading task builds them itself rather than in a child task.
    struct AudioStores {
        let weather: WeatherSystem?
        let sound: SoundRecordStore
        let footstep: FootstepStore
        let materialTypes: MaterialTypeIndex
        let acousticSpaces: AcousticSpaceStore
        let music: MusicRecordStore

        init(file: ESMFile) {
            weather = WeatherSystem(
                file: file, worldspaceEditorID: FirstRenderCell.worldspaceEditorID
            )
            sound = SoundRecordStore(file: file)
            footstep = FootstepStore(file: file)
            materialTypes = MaterialTypeIndex(file: file)
            acousticSpaces = AcousticSpaceStore(file: file)
            music = MusicRecordStore(file: file)
        }
    }

    /// The `Sendable` record stores, each built in its own child task.
    struct RecordStores: Sendable {
        let dialogue: DialogueStore
        let packages: PackageStore
        let world: WorldRecords
        let equipment: EquipmentCatalog
        let actorValueBaselines: ActorValueBaselineResolver
        let scripted: ScriptedData
        let loadOrder: LoadOrderStores
    }

    /// Globals, locations, and the faction graph.
    struct WorldRecords: Sendable {
        let globals: GlobalStore
        let locations: LocationStore
        let factions: FactionStore
        let relationships: RelationshipStore
        let formLists: FormListStore
    }

    /// Owns the builder, which never reaches the main actor.
    let runner: SerialCellBuildRunner
    let scriptFileSystem: any GameFileSource
    let scriptFormIDResolver: FormIDResolver
    /// Plugin the item indexes were built from, which magic-item EFID links are
    /// relative to.
    let magicItemPluginName: String
    let tuning: SettingIndexes
    let magic: MagicIndexes
    let audio: AudioStores
    let inventoryBaselines: InventoryBaselineResolver
    let craftingCatalog: CraftingCatalog
    let records: RecordStores

    func makeSession() -> CellSession {
        CellSession(runner: runner, data: makeDataStores())
    }

    private func makeDataStores() -> WorldDataStores {
        var stores = WorldDataStores(
            scriptFormIDResolver: scriptFormIDResolver,
            scriptFileSystem: scriptFileSystem,
            weatherSystem: audio.weather,
            soundStore: audio.sound,
            footstepStore: audio.footstep,
            materialTypes: audio.materialTypes,
            aspcStore: audio.acousticSpaces,
            musicStore: audio.music,
            globalStore: records.world.globals,
            questStore: records.scripted.quests,
            locationStore: records.world.locations,
            dialogueStore: records.dialogue,
            packageStore: records.packages,
            inventoryBaselines: inventoryBaselines,
            equipmentCatalog: records.equipment,
            actorValueBaselines: records.actorValueBaselines,
            magicEffectStore: magic.effects,
            magicItemPluginName: magicItemPluginName,
            spellStore: magic.spells,
            equipSlotStore: magic.equipSlots,
            enchantmentStore: magic.enchantments,
            perkStore: magic.perks,
            factionStore: records.world.factions,
            relationshipStore: records.world.relationships,
            formListStore: records.world.formLists,
            actorValueInformation: magic.actorValues,
            skillAdvancementSettings: tuning.skillAdvancement,
            characterLevelSettings: tuning.characterLevel,
            movementConfiguration: tuning.movement,
            barterPricing: tuning.barter,
            combatSettings: tuning.combat,
            archerySettings: tuning.archery,
            detectionSettings: tuning.detection
        )
        stores.craftingCatalog = craftingCatalog
        stores.lockTrapData = records.scripted.lockTrap
        stores.storyData = records.scripted.story
        stores.idleStore = records.loadOrder.idles
        stores.effectRecords = records.loadOrder.effects
        stores.presentationRecords = records.loadOrder.presentation
        stores.menuRecords = records.loadOrder.menus
        stores.difficultySettings = tuning.difficulty
        return stores
    }
}

nonisolated extension CellProviderIndexes {
    /// Lock, trap, quest, scene, and story-manager data: what quest and trap scripts
    /// act on. Quests, scenes, and story nodes come from every active plugin.
    struct ScriptedData: Sendable {
        let lockTrap: LockTrapData
        let story: StoryData
        let quests: QuestStore

        init(
            _ plugins: [(name: String, file: ESMFile)],
            _ file: ESMFile,
            _ pluginName: String,
            _ settings: GameSettingStore
        ) {
            lockTrap = LockTrapData.load(
                plugins: plugins, baseFile: file, baseName: pluginName, settings: settings
            )
            story = StoryData.load(plugins: plugins)
            quests = QuestStore(plugins: plugins)
        }
    }

    /// Stores built over the whole active load order.
    struct LoadOrderStores: Sendable {
        let idles: IdleStore
        let effects: EffectRecordStore
        let presentation: PresentationRecordStore
        let menus: MenuRecordData
    }
}
