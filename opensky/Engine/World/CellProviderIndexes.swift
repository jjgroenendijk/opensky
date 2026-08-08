// Complete index set backing the streamed-cell provider. Keeping this
// assembly outside AppDelegate makes additions testable without app startup.

import Metal

nonisolated struct CellProviderIndexes {
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
    let inventoryBaselines: InventoryBaselineResolver
    let equipmentCatalog: EquipmentCatalog
    let actorValueBaselines: ActorValueBaselineResolver
    let movementConfiguration: PlayerMovementConfiguration
    let barterPricing: BarterPricing
    let combatSettings: CombatSettings
    let archerySettings: ArcherySettings

    init(
        root: GameDataRoot,
        fileSystem: VirtualFileSystem,
        device: MTLDevice,
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
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        builder = CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
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
        inventoryBaselines = InventoryBaselineResolver.build(from: file)
        equipmentCatalog = EquipmentCatalog.build(from: file)
        actorValueBaselines = ActorValueBaselineResolver(
            resolver: ActorValueResolver.build(
                from: file,
                localized: (try? file.pluginHeader().isLocalized) ?? false,
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
            inventoryBaselines: inventoryBaselines,
            equipmentCatalog: equipmentCatalog,
            actorValueBaselines: actorValueBaselines,
            movementConfiguration: movementConfiguration,
            barterPricing: barterPricing,
            combatSettings: combatSettings,
            archerySettings: archerySettings
        )
    }
}
