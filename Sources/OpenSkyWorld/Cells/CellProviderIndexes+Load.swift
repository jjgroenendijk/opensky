// Builds the index set off the main actor, in reported stages. Stores that do
// not depend on each other build in parallel child tasks.

import Metal
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyRendering
import OpenSkyWorldState

nonisolated extension CellProviderIndexes {
    /// The values every stage reads. All `Sendable`, so a child task can take them.
    struct LoadContext: Sendable {
        let file: ESMFile
        let pluginName: String
        let plugins: [(name: String, file: ESMFile)]
        let tuning: SettingIndexes
        let progress: WorldLoadProgress
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
        progress: WorldLoadProgress = .silent
    ) async throws -> sending CellSession {
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try progress.measure(.masterFile) { try ESMFile(url: esmURL) }
        // Every load-order store reads this one list, so each plugin opens once.
        let plugins = try progress.measure(.loadOrder) {
            ActivePluginFiles.load(root: root, baseFile: file)
        }
        let tuning = try progress.measure(.settings) { SettingIndexes(plugins: plugins) }
        // The item index resolves enchantments, so magic comes before the fan-out.
        let magic = try progress.measure(.magic) { MagicIndexes(plugins: plugins) }
        let context = LoadContext(
            file: file,
            pluginName: esmURL.lastPathComponent,
            plugins: plugins,
            tuning: tuning,
            progress: progress
        )
        async let records = RecordStores.load(context)
        let (runner, formIDResolver) = try progress.measure(.assetLibraries) {
            try makeRunner(
                file: file,
                fileSystem: fileSystem,
                device: device,
                localizationLanguage: localizationLanguage,
                terrainLODConfigurationStore: terrainLODConfigurationStore
            )
        }
        let audio = try progress.measure(.weatherAndSound) { AudioStores(file: file) }
        let inventory = try progress.measure(.items) {
            inventoryBaselines(context, magic.enchantments, fileSystem, localizationLanguage)
        }
        let crafting = try progress.measure(.crafting) {
            CraftingCatalog(
                recipes: RecipeStore(plugins: plugins),
                itemPlugin: formIDResolver,
                file: file
            )
        }
        return try await CellProviderIndexes(
            runner: runner,
            scriptFileSystem: fileSystem,
            scriptFormIDResolver: formIDResolver,
            magicItemPluginName: context.pluginName,
            tuning: tuning,
            magic: magic,
            audio: audio,
            inventoryBaselines: inventory,
            craftingCatalog: crafting,
            records: records
        ).makeSession()
    }

    /// Hands the new builder straight to the runner, so no other code holds it.
    private static func makeRunner(
        file: ESMFile,
        fileSystem: any GameFileSource,
        device: any MTLDevice,
        localizationLanguage: String,
        terrainLODConfigurationStore: TerrainLODConfigurationStore
    ) throws -> (SerialCellBuildRunner, FormIDResolver) {
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
            localizationLanguage: localizationLanguage,
            terrainLODConfigurationStore: terrainLODConfigurationStore
        )
        let formIDResolver = builder.formIDResolver
        let runner = SerialCellBuildRunner(provider: BuilderCellSceneProvider(
            builder: builder,
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID
        ))
        return (runner, formIDResolver)
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
            from: context.file,
            enchantments: ItemEnchantmentResolver(
                store: enchantments,
                pluginName: context.pluginName
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
        async let packages = progress.measure(.packages) { PackageStore(file: file) }
        async let world = progress.measure(.factions) {
            CellProviderIndexes.WorldRecords(context)
        }
        async let equipment = progress.measure(.equipment) {
            EquipmentCatalog.build(from: file)
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
            (
                PresentationRecordStore(plugins: context.plugins),
                MenuRecordData(file: file, plugins: context.plugins, settings: context.tuning.store)
            )
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
                from: context.file,
                localized: context.file.isLocalized,
                pluginName: context.pluginName,
                // Load-order wide, so a patch plugin's CLAS override reaches the derivation.
                classes: CharacterClassStore(plugins: context.plugins),
                settings: context.tuning.level
            )
        )
    }
}

nonisolated extension CellProviderIndexes.WorldRecords {
    init(_ context: CellProviderIndexes.LoadContext) {
        globals = GlobalStore(file: context.file, pluginName: context.pluginName)
        locations = LocationStore(plugins: context.plugins)
        factions = FactionStore(plugins: context.plugins)
        relationships = RelationshipStore(plugins: context.plugins)
        formLists = FormListStore(plugins: context.plugins)
    }
}
