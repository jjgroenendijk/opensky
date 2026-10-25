// Builds the index set off the main actor, in reported stages. Stores that do
// not depend on each other build in parallel child tasks.

import Metal
import OpenSkyAIPackages
import OpenSkyAssetCache
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyTerrain
import OpenSkyWorldState

nonisolated extension CellProviderIndexes {
    /// The values every stage reads. All `Sendable`, so a child task can take them.
    struct LoadContext: Sendable {
        let file: ESMFile
        /// The master's file name; its string tables carry this name.
        let pluginName: String
        let plugins: [(name: String, file: ESMFile)]
        /// The same plugins; stores built over it read records in the load-order space.
        let loadOrder: LoadOrderPlugins
        let tuning: SettingIndexes
        let progress: WorldLoadProgress
        let fileSystem: any GameFileSource
        /// Built first, because a leveled list's `LVLG` chance reads it.
        let globals: GlobalStore
        /// The one roller every actor, inventory, and package resolver shares.
        let leveling: LeveledListRoller
    }

    /// `LVLG` reads a global's plugin value.
    private static func roller(tuning: SettingIndexes, globals: GlobalStore) -> LeveledListRoller {
        LeveledListRoller(
            settings: tuning.leveledLists,
            chanceNoneGlobal: { globals.global($0)?.defaultValue.value }
        )
    }

    /// Builds the whole set and returns the session over it. Throws
    /// `CancellationError` when the calling task is cancelled.
    @concurrent
    public static func loadSession(
        root: GameDataRoot,
        fileSystem: any GameFileSource,
        device: any MTLDevice,
        localizationLanguage: String = LocalizationLanguageSettings.fallback,
        terrainLODConfigurationStore: TerrainLODConfigurationStore,
        progress: WorldLoadProgress = .silent,
        assetCache: AssetCacheReader? = nil,
        fastLoad: FastTextureLoadControl? = nil,
        loadPhases: LoadPhaseRecorder? = nil
    ) async throws -> sending CellSession {
        let file = try progress.measure(.masterFile) {
            try ActiveLoadOrder.openBaseFile(root: root)
        }
        // Every load-order store reads this one list, so each plugin opens once.
        let activeLoadOrder = try progress.measure(.loadOrder) {
            ActiveLoadOrder(root: root, baseFile: file)
        }
        let plugins = activeLoadOrder.files
        let tuning = try progress.measure(.settings) { SettingIndexes(plugins: plugins) }
        // The item index resolves enchantments, so magic comes before the fan-out.
        let magic = try progress.measure(.magic) { MagicIndexes(plugins: plugins) }
        let globals = GlobalStore(loadOrder: activeLoadOrder.plugins)
        let context = LoadContext(
            file: file,
            pluginName: ActiveLoadOrder.baseFileName,
            plugins: plugins,
            loadOrder: activeLoadOrder.plugins,
            tuning: tuning,
            progress: progress,
            fileSystem: fileSystem,
            globals: globals,
            leveling: roller(tuning: tuning, globals: globals)
        )
        async let records = RecordStores.load(context)
        let built = try progress.measure(.assetLibraries) {
            try makeRunner(
                plugins: context,
                assets: RunnerAssets(
                    fileSystem: fileSystem, device: device, cache: assetCache, fastLoad: fastLoad,
                    loadPhases: loadPhases
                ),
                localizationLanguage: localizationLanguage,
                terrainLODConfigurationStore: terrainLODConfigurationStore
            )
        }
        let audio = try progress
            .measure(.weatherAndSound) { AudioStores(loadOrder: context.loadOrder) }
        let inventory = try progress.measure(.items) {
            inventoryBaselines(context, magic.enchantments, fileSystem, localizationLanguage)
        }
        let crafting = try progress.measure(.crafting) {
            CraftingCatalog(
                recipes: RecipeStore(plugins: plugins),
                itemPlugin: built.formIDResolver,
                loadOrder: context.loadOrder
            )
        }
        return try await CellProviderIndexes(
            runner: built.runner,
            placedRecords: built.placedRecords,
            scriptFileSystem: fileSystem,
            scriptFormIDResolver: built.formIDResolver,
            magicItemPluginName: FormIDResolver.loadOrderSpaceName,
            tuning: tuning,
            magic: magic,
            audio: audio,
            inventoryBaselines: inventory,
            craftingCatalog: crafting,
            records: records
        ).makeSession()
    }

    /// The runner and the builder values the main actor keeps.
    private struct BuiltRunner {
        let runner: SerialCellBuildRunner
        let formIDResolver: FormIDResolver
        let placedRecords: PlacedRecordLookup
    }

    /// Where the asset libraries read from.
    private struct RunnerAssets {
        let fileSystem: any GameFileSource
        let device: any MTLDevice
        let cache: AssetCacheReader?
        /// Nil, or no cache, loads every texture on the CPU.
        let fastLoad: FastTextureLoadControl?
        /// Times the streamer's builds by asset phase, for the benchmark's arrivals.
        let loadPhases: LoadPhaseRecorder?
    }

    /// Hands the new builder straight to the runner, so no other code holds it.
    private static func makeRunner(
        plugins context: LoadContext,
        assets: RunnerAssets,
        localizationLanguage: String,
        terrainLODConfigurationStore: TerrainLODConfigurationStore
    ) throws -> BuiltRunner {
        let fileSystem: any GameFileSource = assets.loadPhases
            .map { PhaseTimedFileSource(base: assets.fileSystem, recorder: $0) } ?? assets
            .fileSystem
        let textures = try TextureLibrary(fileSystem: fileSystem, device: assets.device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: assets.device, textures: textures)
        textures.assetCache = assets.cache
        meshes.assetCache = assets.cache
        if let control = assets.fastLoad, assets.cache != nil {
            textures.fastLoader = try FastTextureLoader(device: assets.device, control: control)
        }
        let builder = CellSceneBuilder(
            file: context.file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
            pluginName: context.pluginName,
            plugins: context.plugins,
            localizationLanguage: localizationLanguage,
            terrainLODConfigurationStore: terrainLODConfigurationStore
        )
        builder.collisionModels?.assetCache = assets.cache
        builder.leveling = context.leveling
        builder.loadPhases = assets.loadPhases
        let formIDResolver = builder.formIDResolver
        let placedRecords = builder.placedRecords
        let lodPrebuild = builder.distantLODBuilder?.prebuild(
            worldspace: FirstRenderCell.worldspaceEditorID
        )
        let runner = SerialCellBuildRunner(
            provider: BuilderCellSceneProvider(
                builder: builder,
                worldspaceEditorID: FirstRenderCell.worldspaceEditorID
            ),
            lodPrebuild: lodPrebuild
        )
        return BuiltRunner(
            runner: runner, formIDResolver: formIDResolver, placedRecords: placedRecords
        )
    }

    /// Item names resolve through the string tables while the index is built.
    /// Built after the ENCH store, so an enchanted item's `EITM` is already resolved.
    private static func inventoryBaselines(
        _ context: LoadContext,
        _ enchantments: EnchantmentStore,
        _ fileSystem: any GameFileSource,
        _ language: String
    ) -> InventoryBaselineResolver {
        InventoryBaselineResolver.build(
            from: context.loadOrder,
            leveling: context.leveling,
            enchantments: ItemEnchantmentResolver(
                store: enchantments,
                pluginName: FormIDResolver.loadOrderSpaceName
            ),
            strings: LocalizedStrings(
                vfs: fileSystem,
                pluginName: context.pluginName,
                language: language
            )
        )
    }
}

nonisolated extension CellProviderIndexes.RecordStores {
    /// One child task per stage. The slowest stage sets the wall time.
    static func load(_ context: CellProviderIndexes.LoadContext) async throws -> Self {
        let progress = context.progress
        let file = context.file
        async let dialogue = progress.measure(.dialogue) {
            DialogueStore(plugins: context.plugins)
        }
        async let packages = progress.measure(.packages) {
            PackageStore(loadOrder: context.loadOrder, leveling: context.leveling)
        }
        async let world = progress.measure(.factions) {
            CellProviderIndexes.WorldRecords(context)
        }
        async let equipment = progress.measure(.equipment) {
            EquipmentCatalog.build(from: context.loadOrder)
        }
        async let actorValues = progress.measure(.actorStats) {
            actorValueBaselines(context)
        }
        async let scripted = progress.measure(.quests) {
            CellProviderIndexes.ScriptedData(
                context.plugins, file, context.pluginName, context.tuning.store
            )
        }
        async let idles = progress.measure(.idlesAndEffects) {
            (IdleStore(plugins: context.plugins), EffectRecordStore(plugins: context.plugins))
        }
        async let menus = progress.measure(.menusAndMessages) {
            var menuData = MenuRecordData(
                loadOrder: context.loadOrder, settings: context.tuning.store
            )
            menuData.chargenTypes = menuData.readChargenTypes(fileSystem: context.fileSystem)
            return (PresentationRecordStore(plugins: context.plugins), menuData)
        }
        let (idleStore, effects) = try await idles
        let (presentation, menuData) = try await menus
        return try await Self(
            dialogue: dialogue,
            packages: packages,
            world: world,
            equipment: equipment,
            actorValueBaselines: actorValues,
            scripted: scripted,
            loadOrder: CellProviderIndexes.LoadOrderStores(
                idles: idleStore,
                effects: effects,
                presentation: presentation,
                menus: menuData
            )
        )
    }

    /// The stat derivation and the baselines over it share one
    /// `PlayerLevelSource`, so a level-up moves NPC scaling and the player's level together.
    private static func actorValueBaselines(
        _ context: CellProviderIndexes.LoadContext
    ) -> ActorValueBaselineResolver {
        ActorValueBaselineResolver(
            resolver: ActorValueResolver.build(
                from: context.loadOrder,
                // Load-order wide, so a patch plugin's CLAS override reaches the derivation.
                classes: CharacterClassStore(plugins: context.plugins),
                pluginName: FormIDResolver.loadOrderSpaceName,
                settings: context.tuning.level,
                leveling: context.leveling
            )
        )
    }
}

nonisolated extension CellProviderIndexes.WorldRecords {
    init(_ context: CellProviderIndexes.LoadContext) {
        globals = context.globals
        locations = LocationStore(plugins: context.plugins)
        factions = FactionStore(plugins: context.plugins)
        relationships = RelationshipStore(plugins: context.plugins)
        formLists = FormListStore(plugins: context.plugins)
        encounterZones = EncounterZoneStore(plugins: context.plugins)
    }
}
