// Every player setting with its default and range. Vanilla rows keep the menu
// order measured with `openskycli swf system-menu`; a row no engine system reads
// yet is marked not applied. See docs/engine/settings.md.

import Foundation

nonisolated public struct PlayerSettingsCatalog: Sendable {
    public let definitions: [PlayerSettingDefinition]
    private let index: [PlayerSettingID: Int]

    public init(definitions: [PlayerSettingDefinition]) {
        self.definitions = definitions
        var index: [PlayerSettingID: Int] = [:]
        for (position, definition) in definitions.enumerated() where index[definition.id] == nil {
            index[definition.id] = position
        }
        self.index = index
    }

    public func definition(_ id: PlayerSettingID) -> PlayerSettingDefinition? {
        index[id].map { definitions[$0] }
    }

    public func definitions(in group: PlayerSettingGroup) -> [PlayerSettingDefinition] {
        definitions.filter { $0.group == group }
    }

    /// The menu-flagged `SNCT` categories the vanilla Audio page lists after Master.
    public static let audioCategoryEditorIDs = [
        ("AudioCategorySFX", "$Effects"), ("AudioCategoryFST", "$Footsteps"),
        ("AudioCategoryVOCGeneral", "$Voice"), ("AudioCategoryMUS", "$Music")
    ]

    /// Difficulty options in menu order. Level 2, Normal (Adept), is the default.
    public static let difficultyOptions = [
        "$Very Easy", "$Easy", "$Normal", "$Hard", "$Very Hard", "$Legendary"
    ]

    public static let saveOnPauseOptions = [
        "$5 Mins", "$10 Mins", "$15 Mins", "$30 Mins", "$45 Mins", "$60 Mins", "$Disabled"
    ]

    /// Settings stored as text rather than as a number.
    public static let textSettingIDs: Set<PlayerSettingID> = [.assetOptimisationFolder]

    public static let vanilla = PlayerSettingsCatalog(
        definitions: gameplay + display + audio + opensky + GraphicsOptions.definitions
    )

    private static let unit = PlayerSettingKind.slider(range: 0 ... 1, step: 0.05)

    private static func row(
        _ id: String, _ group: PlayerSettingGroup, _ kind: PlayerSettingKind,
        _ title: String, _ value: Double, applied: Bool = false
    ) -> PlayerSettingDefinition {
        PlayerSettingDefinition(
            id: PlayerSettingID(id), group: group, kind: kind, title: title,
            defaultValue: value, isApplied: applied
        )
    }

    private static let gameplay: [PlayerSettingDefinition] = [
        row("gameplay.invertY", .gameplay, .toggle, "$Invert Y", 0, applied: true),
        row("gameplay.lookSensitivity", .gameplay, unit, "$Look Sensitivity", 0.5, applied: true),
        row("gameplay.vibration", .gameplay, .toggle, "$Vibration", 1),
        row("gameplay.controller", .gameplay, .toggle, "$360 Controller", 0),
        row(
            "gameplay.missingCreationsCheck",
            .gameplay,
            .toggle,
            "$SaveGameMissingCreationsCheck",
            1
        ),
        row("gameplay.survivalMode", .gameplay, .toggle, "$Survival Mode", 0),
        row(
            "gameplay.difficulty",
            .gameplay,
            .choice(options: difficultyOptions),
            "$Difficulty",
            2,
            applied: true
        ),
        row(
            "gameplay.showFloatingMarkers",
            .gameplay,
            .toggle,
            "$Show Floating Markers",
            1,
            applied: true
        ),
        row("gameplay.saveOnRest", .gameplay, .toggle, "$Save on Rest", 1, applied: true),
        row("gameplay.saveOnWait", .gameplay, .toggle, "$Save on Wait", 1, applied: true),
        row("gameplay.saveOnTravel", .gameplay, .toggle, "$Save on Travel", 1, applied: true),
        row(
            "gameplay.saveOnPause",
            .gameplay,
            .choice(options: saveOnPauseOptions),
            "$Save on Pause",
            6,
            applied: true
        ),
        row("gameplay.useKinect", .gameplay, .toggle, "$Use Kinect Commands", 0)
    ]

    private static let display: [PlayerSettingDefinition] = [
        row("display.brightness", .display, unit, "$Brightness", 0.5),
        row("display.hudOpacity", .display, unit, "$HUD Opacity", 1, applied: true),
        row("display.actorFade", .display, unit, "$Actor Fade", 0.5),
        row("display.itemFade", .display, unit, "$Item Fade", 0.5),
        row("display.objectFade", .display, unit, "$Object Fade", 0.5),
        row("display.grassFade", .display, unit, "$Grass Fade", 0.5),
        row("display.shadowFade", .display, unit, "$Shadow Fade", 0.5),
        row("display.lightFade", .display, unit, "$Light Fade", 0.5),
        row("display.specularityFade", .display, unit, "$Specularity Fade", 0.5),
        row("display.treeLODFade", .display, unit, "$Tree LOD Fade", 0.5),
        row("display.crosshair", .display, .toggle, "$Crosshair", 1, applied: true),
        row(
            "display.dialogueSubtitles",
            .display,
            .toggle,
            "$Dialogue Subtitles",
            0,
            applied: true
        ),
        row("display.generalSubtitles", .display, .toggle, "$General Subtitles", 0, applied: true),
        row("display.ddofIntensity", .display, unit, "$DDOF Intensity", 1)
    ]

    private static let audio: [PlayerSettingDefinition] =
        [row("audio.master", .audio, unit, "$Master", 1, applied: true)]
            + audioCategoryEditorIDs.map { editorID, title in
                row(
                    PlayerSettingID.categoryVolume(editorID).rawValue, .audio, unit, title, 1,
                    applied: true
                )
            }

    /// Rows the vanilla pages do not have. The menu shows none of them.
    private static let opensky: [PlayerSettingDefinition] = [
        row("opensky.compass", .opensky, .toggle, "Compass", 1, applied: true),
        row("opensky.sound", .opensky, .toggle, "Sound", 1, applied: true),
        row(
            "opensky.startAtTitleScreen",
            .opensky,
            .toggle,
            "Start at title screen",
            0,
            applied: true
        ),
        row(
            "assetOptimisation.enabled", .opensky, .toggle, "Use optimised files", 1,
            applied: true
        ),
        row(
            "assetOptimisation.textureQuality",
            .opensky,
            .choice(options: textureQualityOptions),
            "Texture quality",
            0,
            applied: true
        ),
        row(
            "assetOptimisation.directLoad",
            .opensky,
            .toggle,
            "Direct GPU loading",
            1,
            applied: true
        ),
        row(
            "assetOptimisation.directLoad.textures", .opensky, .toggle,
            "Direct GPU loading: textures", 1, applied: true
        ),
        row(
            "assetOptimisation.directLoad.meshes", .opensky, .toggle,
            "Direct GPU loading: meshes", 0, applied: true
        ),
        row(
            "assetOptimisation.directLoad.allDisks", .opensky, .toggle,
            "Direct GPU loading: all disks", 0, applied: true
        ),
        row("pipelineCache.enabled", .opensky, .toggle, "Cache GPU pipelines", 1, applied: true),
        row("rendering.gpuCulling", .opensky, .toggle, "Cull on the GPU", 1, applied: true),
        row("rendering.roomCulling", .opensky, .toggle, "Cull hidden rooms", 1, applied: true),
        row("rendering.waterDepth", .opensky, .toggle, "See into shallow water", 1, applied: true),
        row(
            "rendering.terrainNormalMaps", .opensky, .toggle, "Terrain normal maps", 1,
            applied: true
        ),
        row("rendering.impactEffects", .opensky, .toggle, "Impact effects", 1, applied: true),
        row("rendering.lightAnimation", .opensky, .toggle, "Flickering lights", 1, applied: true),
        row(
            "rendering.particleSorting", .opensky, .toggle, "Sort particles far to near", 1,
            applied: true
        ),
        row("rendering.toneMapping", .opensky, .toggle, "HDR tone mapping", 1, applied: true),
        row(
            "rendering.textureStreaming",
            .opensky,
            .toggle,
            "Full detail only near the camera",
            1,
            applied: true
        ),
        row(
            "rendering.textureBudget",
            .opensky,
            .choice(options: TextureBudget.choiceTitles),
            "Memory for close-up detail",
            0,
            applied: true
        ),
        row(
            "rendering.rayTracedShadows", .opensky, .toggle, "Ray-traced sun shadows", 0,
            applied: true
        ),
        row(
            "rendering.renderScale",
            .opensky,
            .choice(options: renderScaleOptions),
            "Render scale (MetalFX upscaling)",
            0,
            applied: true
        ),
        row(
            "rendering.upscaler",
            .opensky,
            .choice(options: upscalerOptions),
            "Upscaler",
            0,
            applied: true
        ),
        row(
            "rendering.frameInterpolation", .opensky, .toggle, "Frame interpolation (MetalFX)", 0,
            applied: true
        ),
        row(
            "rendering.meshShaderGrass", .opensky, .toggle, "Mesh-shader grass", 0, applied: true
        ),
        row("window.fullScreen", .opensky, .toggle, "Full screen", 0, applied: true),
        row(
            "window.frameRateCap", .opensky,
            .choice(options: frameRateCapOptions.map(frameRateCapTitle)),
            "Frame rate cap", 0, applied: true
        )
    ] + assetKindRows + textureFormatRows + characterRows
}

nonisolated extension PlayerSettingsCatalog {
    /// The frame rate caps in menu order; 0 is no cap.
    public static let frameRateCapOptions = [0, 30, 60, 120]

    /// `Off` or `60 fps`.
    public static func frameRateCapTitle(_ cap: Int) -> String {
        cap == 0 ? "Off" : "\(cap) fps"
    }

    /// One switch per optimised asset kind; off reads that kind from the archives.
    /// Audio and animation have none: they are not optimised.
    private static let assetKindRows = [
        ("textures", "Optimise textures"), ("meshes", "Optimise meshes"),
        ("collision", "Optimise collision")
    ].map { folder, title in
        row("assetOptimisation.kind.\(folder)", .opensky, .toggle, title, 1, applied: true)
    }

    /// A format forced per texture group, in `TextureFormatChoice` raw-value order.
    private static let textureFormatRows = [
        ("color", "Colour texture format"), ("normal", "Normal map format"),
        ("data", "Data map format")
    ].map { group, title in
        row(
            "assetOptimisation.textureFormat.\(group)", .opensky,
            .choice(options: textureFormatOptions), title, 0, applied: true
        )
    }

    /// The texture streaming budget choices, in MiB.
    public static let textureBudgetOptions = [128, 256, 512, 1024, 2048]

    /// In `RenderScale.percentOptions` order.
    public static let renderScaleOptions = ["Off", "50%", "59%", "67%", "75%", "85%", "100%"]

    /// In `UpscalerKind` raw-value order.
    public static let upscalerOptions = ["Temporal", "Spatial"]

    /// In `TextureQuality` raw-value order.
    public static let textureQualityOptions = ["Original", "High", "Medium", "Low"]

    /// In `TextureFormatChoice` raw-value order.
    public static let textureFormatOptions = [
        "Automatic", "Shipped", "ASTC 4x4", "ASTC 5x5", "ASTC 6x6", "ASTC 8x8"
    ]

    /// Ids a later version renamed. Old files are read with the new names.
    public static let renamedIDs: [String: String] = [
        "assetCache.enabled": "assetOptimisation.enabled",
        "assetCache.folder": "assetOptimisation.folder",
        "assetCache.fastLoad": "assetOptimisation.directLoad.textures",
        "assetCache.fastMeshLoad": "assetOptimisation.directLoad.meshes",
        "assetCache.kind.textures": "assetOptimisation.kind.textures",
        "assetCache.kind.meshes": "assetOptimisation.kind.meshes",
        "assetCache.kind.collision": "assetOptimisation.kind.collision"
    ]
}

nonisolated extension PlayerSettingID {
    /// The optimised files folder. No value means the default folder.
    public static let assetOptimisationFolder = Self("assetOptimisation.folder")
    public static let assetOptimisationEnabled = Self("assetOptimisation.enabled")
    /// A `TextureQuality` raw value.
    public static let textureQuality = Self("assetOptimisation.textureQuality")
    /// Optimised files read straight into GPU memory during a cell build.
    public static let directGPULoading = Self("assetOptimisation.directLoad")
    public static let directGPULoadingTextures = Self("assetOptimisation.directLoad.textures")
    public static let directGPULoadingMeshes = Self("assetOptimisation.directLoad.meshes")
    public static let directGPULoadingAllDisks = Self("assetOptimisation.directLoad.allDisks")
    /// Pipelines load from the archive an earlier launch saved.
    public static let pipelineCacheEnabled = Self("pipelineCache.enabled")
    /// The static scene culls in a compute pass; off culls it on the CPU.
    public static let gpuCulling = Self("rendering.gpuCulling")
    /// An interior draws only the rooms the camera sees through portals.
    public static let roomCulling = Self("rendering.roomCulling")
    /// Water reads the scene depth, so shallow water shows the ground below it.
    public static let waterDepth = Self("rendering.waterDepth")
    /// Terrain lighting follows the land textures' normal maps.
    public static let terrainNormalMaps = Self("rendering.terrainNormalMaps")
    /// A hit or a step shows its impact model: dust, sparks, or blood spray.
    public static let impactEffects = Self("rendering.impactEffects")
    /// Placed lights flicker and pulse as their light records ask.
    public static let lightAnimation = Self("rendering.lightAnimation")
    /// Blended particles and their systems draw far to near.
    public static let particleSorting = Self("rendering.particleSorting")
    /// The eye adapts to the scene brightness and the image space white point applies.
    public static let toneMapping = Self("rendering.toneMapping")
    /// The game's `[Decals] bDecals` and `[Display] uMaxDecals`.
    public static let decals = Self("graphics.bDecals")
    public static let decalLimit = Self("graphics.uMaxDecals")
    /// Large textures keep only the mip levels the camera needs.
    public static let textureStreaming = Self("rendering.textureStreaming")
    /// An index into `TextureBudget.choiceTitles`: 0 is Automatic.
    public static let textureBudget = Self("rendering.textureBudget")
    /// Traces sun shadows on GPUs with hardware ray tracing; ignored elsewhere.
    public static let rayTracedShadows = Self("rendering.rayTracedShadows")
    /// An index into `RenderScale.percentOptions`; 0 is off.
    public static let renderScale = Self("rendering.renderScale")
    /// An `UpscalerKind` raw value.
    public static let upscaler = Self("rendering.upscaler")
    /// Builds a MetalFX frame between real frames; runs only with the temporal upscaler.
    public static let frameInterpolation = Self("rendering.frameInterpolation")
    /// Draws grass with object and mesh shaders that cull meshlets on the GPU.
    public static let meshShaderGrass = Self("rendering.meshShaderGrass")
    public static let fullScreen = Self("window.fullScreen")
    /// Actors blink on their own.
    public static let characterBlinking = Self("characters.blinking")
    /// A speaker's face shows the emotion of the line it says.
    public static let characterDialogueExpressions = Self("characters.dialogueExpressions")
    /// Actors turn their heads toward what they look at.
    public static let characterHeadTracking = Self("characters.headTracking")
    /// Traps, doors, and levers play their behaviour graph animations.
    public static let objectAnimation = Self("world.objectAnimation")
    /// An index into `PlayerSettingsCatalog.frameRateCapOptions`.
    public static let frameRateCap = Self("window.frameRateCap")

    /// The switch of one optimised asset kind, by its folder name.
    public static func assetKind(folder: String) -> Self {
        Self("assetOptimisation.kind.\(folder)")
    }

    /// The forced format of one texture group: `color`, `normal`, or `data`.
    public static func textureFormat(group: String) -> Self {
        Self("assetOptimisation.textureFormat.\(group)")
    }
}

nonisolated extension PlayerSettingsCatalog {
    private static let characterRows: [PlayerSettingDefinition] = [
        row("characters.blinking", .opensky, .toggle, "Blinking", 1, applied: true),
        row(
            "characters.dialogueExpressions", .opensky, .toggle, "Dialogue expressions", 1,
            applied: true
        ),
        row("characters.headTracking", .opensky, .toggle, "Head tracking", 1, applied: true),
        row("world.objectAnimation", .opensky, .toggle, "Animated objects", 1, applied: true)
    ]
}
