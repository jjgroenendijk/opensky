// The OpenSky settings rows of the vanilla catalog.

import Foundation

nonisolated extension PlayerSettingsCatalog {
    static let opensky: [PlayerSettingDefinition] = [
        row(("opensky.compass", .opensky), .toggle, "Compass", 1, applied: true),
        row(("opensky.sound", .opensky), .toggle, "Sound", 1, applied: true),
        row(
            ("opensky.startAtTitleScreen", .opensky),
            .toggle,
            "Start at title screen",
            0,
            applied: true
        ),
        row(
            ("opensky.startupLogo", .opensky),
            .toggle,
            "Play the startup logo",
            1,
            applied: true
        ),
        row(
            ("opensky.survivalModeAsk", .opensky),
            .toggle,
            "Ask about Survival Mode",
            0,
            applied: true
        ),
        row(
            ("assetOptimisation.enabled", .opensky),
            .toggle,
            "Use optimised files",
            1,
            applied: true
        ),
        row(
            ("assetOptimisation.textureQuality", .opensky),
            .choice(options: textureQualityOptions),
            "Texture quality",
            0,
            applied: true
        ),
        row(
            ("assetOptimisation.directLoad", .opensky),
            .toggle,
            "Direct GPU loading",
            1,
            applied: true
        ),
        row(
            ("assetOptimisation.directLoad.textures", .opensky),
            .toggle,
            "Direct GPU loading: textures",
            1,
            applied: true
        ),
        row(
            ("assetOptimisation.directLoad.meshes", .opensky),
            .toggle,
            "Direct GPU loading: meshes",
            0,
            applied: true
        ),
        row(
            ("assetOptimisation.directLoad.allDisks", .opensky),
            .toggle,
            "Direct GPU loading: all disks",
            0,
            applied: true
        ),
        row(("pipelineCache.enabled", .opensky), .toggle, "Cache GPU pipelines", 1, applied: true),
        row(
            ("loading.parallelDecode", .opensky),
            .toggle,
            "Decode assets on every core",
            1,
            applied: true
        ),
        row(("rendering.gpuCulling", .opensky), .toggle, "Cull on the GPU", 1, applied: true),
        row(("rendering.roomCulling", .opensky), .toggle, "Cull hidden rooms", 1, applied: true),
        row(
            ("rendering.waterDepth", .opensky),
            .toggle,
            "See into shallow water",
            1,
            applied: true
        ),
        row(
            ("rendering.terrainNormalMaps", .opensky),
            .toggle,
            "Terrain normal maps",
            1,
            applied: true
        ),
        row(("rendering.impactEffects", .opensky), .toggle, "Impact effects", 1, applied: true),
        row(("rendering.screenBlood", .opensky), .toggle, "Screen blood", 1, applied: true),
        row(("rendering.lowHealthPulse", .opensky), .toggle, "Low-health pulse", 1, applied: true),
        row(
            ("rendering.generatedTerrainLOD", .opensky),
            .toggle,
            "Distant land from the load order",
            1,
            applied: true
        ),
        row(("rendering.lightAnimation", .opensky), .toggle, "Flickering lights", 1, applied: true),
        row(("rendering.characterLight", .opensky), .toggle, "Character light", 1, applied: true),
        row(
            ("rendering.indirectLight", .opensky),
            .toggle,
            "Screen-space indirect light",
            0,
            applied: true
        ),
        row(("rendering.shadowLights", .opensky), .toggle, "Shadows from lights", 1, applied: true),
        row(
            ("rendering.particleSorting", .opensky),
            .toggle,
            "Sort particles far to near",
            1,
            applied: true
        ),
        row(("rendering.toneMapping", .opensky), .toggle, "HDR tone mapping", 1, applied: true),
        row(
            ("rendering.textureStreaming", .opensky),
            .toggle,
            "Full detail only near the camera",
            1,
            applied: true
        ),
        row(
            ("rendering.textureBudget", .opensky),
            .choice(options: TextureBudget.choiceTitles),
            "Memory for close-up detail",
            0,
            applied: true
        ),
        row(
            ("rendering.rayTracedShadows", .opensky),
            .toggle,
            "Ray-traced sun shadows",
            0,
            applied: true
        ),
        row(
            ("rendering.renderScale", .opensky),
            .choice(options: renderScaleOptions),
            "Render scale (MetalFX upscaling)",
            0,
            applied: true
        ),
        row(
            ("rendering.upscaler", .opensky),
            .choice(options: upscalerOptions),
            "Upscaler",
            0,
            applied: true
        ),
        row(
            ("rendering.frameInterpolation", .opensky),
            .toggle,
            "Frame interpolation (MetalFX)",
            0,
            applied: true
        ),
        row(
            ("rendering.meshShaderGrass", .opensky),
            .toggle,
            "Mesh-shader grass",
            0,
            applied: true
        ),
        row(("window.fullScreen", .opensky), .toggle, "Full screen", 0, applied: true),
        row(("developer.agentControl", .opensky), .toggle, "Agent control", 1, applied: true),
        row(
            ("window.frameRateCap", .opensky),
            .choice(options: frameRateCapOptions.map(frameRateCapTitle)),
            "Frame rate cap",
            0,
            applied: true
        )
    ] + assetKindRows + textureFormatRows + characterRows
}
