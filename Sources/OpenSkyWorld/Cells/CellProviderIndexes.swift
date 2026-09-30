// Complete index set backing the streamed-cell provider. Keeping this
// assembly outside AppDelegate makes additions testable without app startup.

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
    /// shared `RecordIndex` so the plugins are walked once. A type, so the outer
    /// initializer stays under its length limit.
    private struct MagicIndexes {
        let effects: MagicEffectStore
        let spells: SpellStore
        let equipSlots: EquipSlotStore
        let enchantments: EnchantmentStore
        /// PERK rides the same index: its ability effects and its
        /// spell-selecting entry-point functions join against the SPEL store
        /// built two lines above, so building it here is one record walk rather
        /// than a second load order resolution for the same plugins.
        let perks: PerkStore
        /// AVIF rides it too: the perk trees this index already
        /// decodes hang off AVIF records, and skill advancement reads the
        /// `AVSK` parameters off the same ones.
        let actorValues: ActorValueInformationStore

        init(root: GameDataRoot, baseFile: ESMFile) {
            let index = RecordIndex(
                plugins: ActivePluginFiles.load(root: root, baseFile: baseFile),
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
    ///
    /// Grouped for the reason `MagicIndexes` is: six resolutions in a row is
    /// six lines the outer initializer does not have to spend, and the group is
    /// a real one — each of these is a settings read and nothing else.
    private struct SettingIndexes {
        let movement: PlayerMovementConfiguration
        let barter: BarterPricing
        let combat: CombatSettings
        let archery: ArcherySettings
        let detection: DetectionSettings
        let skillAdvancement: SkillAdvancementSettings
        let characterLevel: CharacterLevelSettings
        let level: ActorValueLevelSettings

        init(root: GameDataRoot, baseFile: ESMFile) {
            // One GMST load for every consumer: resolving the load order twice
            // would parse every plugin's GMST group twice for the same answer.
            let settings = GameSettingLoader.load(root: root, baseFile: baseFile)
            movement = PlayerMovementConfiguration.resolve(
                store: settings,
                movementTypes: MovementTypeLoader.load(root: root, baseFile: baseFile)
            )
            barter = BarterPricing.resolve(store: settings)
            combat = CombatSettings.resolve(store: settings)
            archery = ArcherySettings.resolve(store: settings)
            detection = DetectionSettings.resolve(store: settings)
            skillAdvancement = SkillAdvancementSettings.resolve(store: settings)
            characterLevel = CharacterLevelSettings.resolve(store: settings)
            level = ActorValueLevelSettings.resolve(store: settings)
        }
    }

    public let builder: CellSceneBuilder
    public let weatherSystem: WeatherSystem?
    public let soundStore: SoundRecordStore
    public let footstepStore: FootstepStore
    public let materialTypes: MaterialTypeIndex
    public let aspcStore: AcousticSpaceStore
    public let musicStore: MusicRecordStore
    public let globalStore: GlobalStore
    public let questStore: QuestStore
    public let locationStore: LocationStore
    public let dialogueStore: DialogueStore
    public let packageStore: PackageStore
    public let inventoryBaselines: InventoryBaselineResolver
    public let equipmentCatalog: EquipmentCatalog
    public let actorValueBaselines: ActorValueBaselineResolver
    /// Load-order MGEF index, behind every EFID an applied effect
    /// resolves.
    public let magicEffectStore: MagicEffectStore
    /// Load-order SPEL and SCRL index, which the spellbook keys
    /// its known spells against.
    public let spellStore: SpellStore
    /// Load-order EQUP index, which answers which hands a readied
    /// spell takes.
    public let equipSlotStore: EquipSlotStore
    /// Load-order ENCH index, behind every enchanted weapon's charge
    /// and every worn item's constant effects.
    public let enchantmentStore: EnchantmentStore
    /// Load-order PERK index, which the perk runtime owns perks
    /// out of.
    public let perkStore: PerkStore
    /// Load-order AVIF index, which skill advancement reads each
    /// skill's `AVSK` parameters out of.
    public let actorValueInformation: ActorValueInformationStore
    /// Load-order FACT index, which every runtime membership is
    /// resolved through.
    public let factionStore: FactionStore
    /// Load-order RELA and ASTP index, which the hostility
    /// derivation asks about one specific pair of actors.
    public let relationshipStore: RelationshipStore
    /// Load-order FLST index, which a vendor faction's buy/sell
    /// keyword list is flattened through.
    public let formListStore: FormListStore
    /// GMST-derived `fSkillUseCurve` and `fXPPerSkillRank`.
    public let skillAdvancementSettings: SkillAdvancementSettings
    /// GMST-derived level curve and level-up rewards.
    public let characterLevelSettings: CharacterLevelSettings
    /// Plugin the item indexes were built from, which magic-item EFID links are
    /// relative to.
    public let magicItemPluginName: String
    public let movementConfiguration: PlayerMovementConfiguration
    public let barterPricing: BarterPricing
    public let combatSettings: CombatSettings
    public let archerySettings: ArcherySettings
    public let detectionSettings: DetectionSettings

    public init(
        root: GameDataRoot,
        fileSystem: VirtualFileSystem,
        device: MTLDevice,
        localizationLanguage: String = LocalizationLanguageSettings.fallback,
        terrainLODConfigurationStore: TerrainLODConfigurationStore
    ) throws {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try ESMFile(url: esmURL)
        let tuning = SettingIndexes(root: root, baseFile: file)
        movementConfiguration = tuning.movement
        barterPricing = tuning.barter
        combatSettings = tuning.combat
        archerySettings = tuning.archery
        detectionSettings = tuning.detection
        skillAdvancementSettings = tuning.skillAdvancement
        characterLevelSettings = tuning.characterLevel
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        builder = CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
            localizationLanguage: localizationLanguage,
            terrainLODConfigurationStore: terrainLODConfigurationStore
        )
        weatherSystem = WeatherSystem(
            file: file,
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID
        )
        soundStore = SoundRecordStore(file: file)
        footstepStore = FootstepStore(file: file)
        materialTypes = MaterialTypeIndex(file: file)
        aspcStore = AcousticSpaceStore(file: file)
        musicStore = MusicRecordStore(file: file)
        globalStore = GlobalStore(file: file, pluginName: esmURL.lastPathComponent)
        questStore = QuestStore(file: file, pluginName: esmURL.lastPathComponent)
        locationStore = LocationStoreLoader.load(root: root, baseFile: file)
        dialogueStore = DialogueStore(file: file, pluginName: esmURL.lastPathComponent)
        packageStore = PackageStore(file: file)
        factionStore = FactionStoreLoader.load(root: root, baseFile: file)
        relationshipStore = RelationshipStoreLoader.load(root: root, baseFile: file)
        formListStore = FormListStoreLoader.load(root: root, baseFile: file)
        let magic = MagicIndexes(root: root, baseFile: file)
        magicEffectStore = magic.effects
        spellStore = magic.spells
        equipSlotStore = magic.equipSlots
        enchantmentStore = magic.enchantments
        perkStore = magic.perks
        actorValueInformation = magic.actorValues
        magicItemPluginName = esmURL.lastPathComponent
        // Built after the ENCH store so every enchanted item's `EITM` arrives
        // already load-order resolved: without the resolver an
        // equipped enchanted weapon would look unenchanted at runtime.
        inventoryBaselines = InventoryBaselineResolver.build(
            from: file,
            enchantments: ItemEnchantmentResolver(
                store: magic.enchantments,
                pluginName: esmURL.lastPathComponent
            )
        )
        equipmentCatalog = EquipmentCatalog.build(from: file)
        actorValueBaselines = Self.actorValueBaselines(
            root: root, file: file, pluginName: esmURL.lastPathComponent, tuning: tuning
        )
    }

    /// The stat derivation and the baselines over it.
    ///
    /// Its own step because the initializer is at its length cap, and because
    /// the two halves have to share one `PlayerLevelSource`: the
    /// baselines take the resolver's own, so a level-up moves an NPC's
    /// `PC Level Mult` scaling and the player's reported level together.
    private static func actorValueBaselines(
        root: GameDataRoot,
        file: ESMFile,
        pluginName: String,
        tuning: SettingIndexes
    ) -> ActorValueBaselineResolver {
        ActorValueBaselineResolver(
            resolver: ActorValueResolver.build(
                from: file,
                localized: (try? file.pluginHeader().isLocalized) ?? false,
                pluginName: pluginName,
                // Load-order wide, so a patch plugin's CLAS override reaches
                // the derivation instead of being invisible to it.
                classes: CharacterClassStoreLoader.load(root: root, baseFile: file),
                settings: tuning.level
            )
        )
    }

    public func makeProvider() -> BuilderCellSceneProvider {
        BuilderCellSceneProvider(
            builder: builder,
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            weatherSystem: weatherSystem,
            soundStore: soundStore,
            footstepStore: footstepStore,
            materialTypes: materialTypes,
            aspcStore: aspcStore,
            musicStore: musicStore,
            globalStore: globalStore,
            questStore: questStore,
            locationStore: locationStore,
            dialogueStore: dialogueStore,
            packageStore: packageStore,
            inventoryBaselines: inventoryBaselines,
            equipmentCatalog: equipmentCatalog,
            actorValueBaselines: actorValueBaselines,
            magicEffectStore: magicEffectStore,
            magicItemPluginName: magicItemPluginName,
            spellStore: spellStore,
            equipSlotStore: equipSlotStore,
            enchantmentStore: enchantmentStore,
            perkStore: perkStore,
            factionStore: factionStore,
            relationshipStore: relationshipStore,
            formListStore: formListStore,
            actorValueInformation: actorValueInformation,
            skillAdvancementSettings: skillAdvancementSettings,
            characterLevelSettings: characterLevelSettings,
            movementConfiguration: movementConfiguration,
            barterPricing: barterPricing,
            combatSettings: combatSettings,
            archerySettings: archerySettings,
            detectionSettings: detectionSettings
        )
    }
}
