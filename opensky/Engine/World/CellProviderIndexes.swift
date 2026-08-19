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

        init(root: GameDataRoot, baseFile: ESMFile) {
            let index = RecordIndex(
                plugins: ActivePluginFiles.load(root: root, baseFile: baseFile),
                recordTypes: ["MGEF", "SPEL", "SCRL", "EQUP", "ENCH"]
            )
            let effects = MagicEffectStore(index: index)
            self.effects = effects
            spells = SpellStore(index: index, effects: effects)
            equipSlots = EquipSlotStore(index: index)
            enchantments = EnchantmentStore(index: index, effects: effects)
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
        // One GMST load for both consumers: resolving the load order twice
        // would parse every plugin's GMST group twice for the same answer.
        let settings = GameSettingLoader.load(root: root, baseFile: file)
        movementConfiguration = PlayerMovementConfiguration.resolve(
            store: settings,
            movementTypes: MovementTypeLoader.load(root: root, baseFile: file)
        )
        barterPricing = BarterPricing.resolve(store: settings)
        combatSettings = CombatSettings.resolve(store: settings)
        archerySettings = ArcherySettings.resolve(store: settings)
        detectionSettings = DetectionSettings.resolve(store: settings)
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
        actorValueBaselines = ActorValueBaselineResolver(
            resolver: ActorValueResolver.build(
                from: file,
                localized: (try? file.pluginHeader().isLocalized) ?? false,
                pluginName: esmURL.lastPathComponent,
                // Load-order wide, so a patch plugin's CLAS override reaches
                // the derivation instead of being invisible to it (#496).
                classes: CharacterClassStoreLoader.load(root: root, baseFile: file),
                settings: ActorValueLevelSettings.resolve(store: settings)
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
            movementConfiguration: movementConfiguration,
            barterPricing: barterPricing,
            combatSettings: combatSettings,
            archerySettings: archerySettings,
            detectionSettings: detectionSettings
        )
    }
}
