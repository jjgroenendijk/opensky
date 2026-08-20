// Complete index set backing the streamed-cell provider. Keeping this
// assembly outside AppDelegate makes additions testable without app startup.

import Metal

nonisolated struct CellProviderIndexes {
    /// The four load-order magic stores, decoded off one shared `RecordIndex`
    /// rather than one load-order scan each: MGEF, SPEL, SCRL, EQUP and ENCH come
    /// off the same index and the plugin files are walked once (issues #470 and
    /// #472). Grouped into a type rather than inlined so the outer initializer
    /// stays inside its length limit.
    private struct MagicIndexes {
        let effects: MagicEffectStore
        let spells: SpellStore
        let equipSlots: EquipSlotStore
        let enchantments: EnchantmentStore
        /// PERK rides the same index (issue #497): its ability effects and its
        /// spell-selecting entry-point functions join against the SPEL store
        /// built two lines above, so building it here is one record walk rather
        /// than a second load order resolution for the same plugins.
        let perks: PerkStore
        /// AVIF rides it too (issue #498): the perk trees this index already
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

    let builder: CellSceneBuilder
    let weatherSystem: WeatherSystem?
    let soundStore: SoundRecordStore
    let footstepStore: FootstepStore
    let materialTypes: MaterialTypeIndex
    /// NAVI decoded once (issue #199). Not passed to the provider: nothing in
    /// the scene build reads a navmesh yet, and the pathing graph that will
    /// (16.2, issue #200) takes it from here directly.
    let navmeshes: NavmeshIndex
    let aspcStore: AcousticSpaceStore
    let musicStore: MusicRecordStore
    let globalStore: GlobalStore
    let questStore: QuestStore
    let locationStore: LocationStore
    let dialogueStore: DialogueStore
    let packageStore: PackageStore
    let inventoryBaselines: InventoryBaselineResolver
    let equipmentCatalog: EquipmentCatalog
    let actorValueBaselines: ActorValueBaselineResolver
    /// Load-order MGEF index (issue #469), behind every EFID an applied effect
    /// resolves.
    let magicEffectStore: MagicEffectStore
    /// Load-order SPEL and SCRL index (issue #470), which the spellbook keys
    /// its known spells against.
    let spellStore: SpellStore
    /// Load-order EQUP index (issue #470), which answers which hands a readied
    /// spell takes.
    let equipSlotStore: EquipSlotStore
    /// Load-order ENCH index (issue #472), behind every enchanted weapon's charge
    /// and every worn item's constant effects.
    let enchantmentStore: EnchantmentStore
    /// Load-order PERK index (issue #497), which the perk runtime owns perks
    /// out of.
    let perkStore: PerkStore
    /// Load-order AVIF index (issue #498), which skill advancement reads each
    /// skill's `AVSK` parameters out of.
    let actorValueInformation: ActorValueInformationStore
    /// GMST-derived `fSkillUseCurve` and `fXPPerSkillRank` (issue #498).
    let skillAdvancementSettings: SkillAdvancementSettings
    /// GMST-derived level curve and level-up rewards (issue #499).
    let characterLevelSettings: CharacterLevelSettings
    /// Plugin the item indexes were built from, which magic-item EFID links are
    /// relative to.
    let magicItemPluginName: String
    let movementConfiguration: PlayerMovementConfiguration
    let barterPricing: BarterPricing
    let combatSettings: CombatSettings
    let archerySettings: ArcherySettings
    let detectionSettings: DetectionSettings

    init(
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
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
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
        navmeshes = NavmeshIndex(file: file)
        aspcStore = AcousticSpaceStore(file: file)
        musicStore = MusicRecordStore(file: file)
        globalStore = GlobalStore(file: file, pluginName: esmURL.lastPathComponent)
        questStore = QuestStore(file: file, pluginName: esmURL.lastPathComponent)
        locationStore = LocationStoreLoader.load(root: root, baseFile: file)
        dialogueStore = DialogueStore(file: file, pluginName: esmURL.lastPathComponent)
        packageStore = PackageStore(file: file)
        let magic = MagicIndexes(root: root, baseFile: file)
        magicEffectStore = magic.effects
        spellStore = magic.spells
        equipSlotStore = magic.equipSlots
        enchantmentStore = magic.enchantments
        perkStore = magic.perks
        actorValueInformation = magic.actorValues
        magicItemPluginName = esmURL.lastPathComponent
        // Built after the ENCH store so every enchanted item's `EITM` arrives
        // already load-order resolved (issue #472): without the resolver an
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
    /// the two halves have to share one `PlayerLevelSource` (issue #499): the
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
                // the derivation instead of being invisible to it (#496).
                classes: CharacterClassStoreLoader.load(root: root, baseFile: file),
                settings: tuning.level
            )
        )
    }

    func makeProvider() -> BuilderCellSceneProvider {
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
