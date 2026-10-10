// The base game's graphics options: every key the install's Low, Medium, High,
// and Ultra preset files set. The values are read from the install at runtime;
// none is copied here. docs/engine/graphics-options.md has the list and sources.

import Foundation

nonisolated public enum GraphicsGroup: String, CaseIterable, Sendable {
    case viewDistance, shadows, lighting, antiAliasing, effects, decals, other

    public var title: String {
        switch self {
        case .viewDistance: "View distance"
        case .shadows: "Shadows"
        case .lighting: "Lighting"
        case .antiAliasing: "Anti-aliasing"
        case .effects: "Effects"
        case .decals: "Decals"
        case .other: "Other"
        }
    }
}

nonisolated public struct GraphicsOption: Equatable, Sendable {
    public let group: GraphicsGroup
    public let title: String
    public let section: String
    public let key: String
    /// Nil when OpenSky applies it; otherwise why it does nothing yet.
    public let unavailableReason: String?

    public var id: PlayerSettingID {
        PlayerSettingID("graphics.\(key)")
    }

    public var isToggle: Bool {
        key.hasPrefix("b")
    }

    /// `[TerrainManager] fBlockLevel0Distance`, for the details view.
    public var iniName: String {
        "[\(section)] \(key)"
    }
}

nonisolated public enum GraphicsOptions {
    private static func option(
        _ group: GraphicsGroup, _ title: String, _ section: String, _ key: String,
        _ reason: String? = nil
    ) -> GraphicsOption {
        GraphicsOption(
            group: group,
            title: title,
            section: section,
            key: key,
            unavailableReason: reason
        )
    }

    private static let noSSAO = "OpenSky has no screen-space ambient occlusion yet"
    private static let noSkinDecals = "OpenSky draws no decals on actors yet"
    private static let fixedFades = "OpenSky fades objects at fixed distances today"

    public static let all: [GraphicsOption] = [
        option(.viewDistance, "Near terrain detail", "TerrainManager", "fBlockLevel0Distance"),
        option(.viewDistance, "Middle terrain detail", "TerrainManager", "fBlockLevel1Distance"),
        option(.viewDistance, "Far terrain distance", "TerrainManager", "fBlockMaximumDistance"),
        option(.viewDistance, "Tree distance", "TerrainManager", "fTreeLoadDistance"),
        option(
            .viewDistance, "Terrain split distance", "TerrainManager", "fSplitDistanceMult",
            "OpenSky splits terrain blocks by its own rule"
        ),
        option(.viewDistance, "Actor fade", "LOD", "fLODFadeOutMultActors", fixedFades),
        option(.viewDistance, "Item fade", "LOD", "fLODFadeOutMultItems", fixedFades),
        option(.viewDistance, "Object fade", "LOD", "fLODFadeOutMultObjects", fixedFades),
        option(.viewDistance, "Grass fade", "Grass", "fGrassStartFadeDistance", fixedFades),
        option(.viewDistance, "Mesh LOD 1 fade", "Display", "fMeshLODLevel1FadeDist", fixedFades),
        option(.viewDistance, "Mesh LOD 2 fade", "Display", "fMeshLODLevel2FadeDist", fixedFades),
        option(
            .viewDistance, "Large object grid", "General", "uLargeRefLODGridSize",
            "OpenSky has no large reference LOD yet"
        ),
        option(
            .shadows,
            "Shadow distance",
            "Display",
            "fShadowDistance",
            "OpenSky sizes its shadow cascades itself"
        ),
        option(
            .shadows, "Shadow resolution", "Display", "iShadowMapResolution",
            "OpenSky picks its shadow map size itself"
        ),
        option(
            .shadows,
            "Focus shadows",
            "Display",
            "iNumFocusShadow",
            "OpenSky has no focus shadows"
        ),
        option(.lighting, "Ambient occlusion", "Display", "bSAOEnable", noSSAO),
        option(
            .lighting,
            "Image-based lighting",
            "Display",
            "bIBLFEnable",
            "OpenSky has no image-based lighting"
        ),
        option(
            .lighting, "Volumetric lighting", "Display", "bVolumetricLightingEnable",
            "OpenSky has no volumetric lighting yet"
        ),
        option(
            .lighting, "Volumetric lighting quality", "Display", "iVolumetricLightingQuality",
            "OpenSky has no volumetric lighting yet"
        ),
        option(
            .lighting, "Screen-space reflections", "Display", "bScreenSpaceReflectionEnabled",
            "OpenSky has no screen-space reflections yet"
        ),
        option(
            .lighting, "High dynamic range target", "Display", "bUse64bitsHDRRenderTarget",
            "OpenSky picks its render target formats itself"
        ),
        option(
            .antiAliasing, "Temporal anti-aliasing", "Display", "bUseTAA",
            "The MetalFX temporal upscaler smooths edges instead"
        ),
        option(.antiAliasing, "FXAA", "Display", "bFXAAEnabled", "OpenSky has no FXAA"),
        option(
            .effects,
            "Depth of field",
            "ImageSpace",
            "bDoDepthOfField",
            "OpenSky has no depth of field yet"
        ),
        option(.effects, "Lens flare", "ImageSpace", "bLensFlare", "OpenSky has no lens flare yet"),
        option(
            .effects,
            "Snow sparkles",
            "Display",
            "bToggleSparkles",
            "OpenSky has no snow sparkles"
        ),
        option(
            .effects,
            "Improved snow",
            "Display",
            "bEnableImprovedSnow",
            "OpenSky has no improved snow shader"
        ),
        option(
            .effects, "Projected diffuse normals", "Display", "bEnableProjecteUVDiffuseNormals",
            "OpenSky has no projected UV shader"
        ),
        option(
            .effects, "Rain occlusion", "Display", "bUsePrecipitationOcclusion",
            "OpenSky does not hide rain under roofs yet"
        ),
        option(.decals, "Decals", "Decals", "bDecals"),
        option(.decals, "Skin decals", "Decals", "bSkinnedDecals", noSkinDecals),
        option(
            .decals, "Decals per frame", "Display", "iMaxDecalsPerFrame",
            "OpenSky places every decal the frame asks for"
        ),
        option(
            .decals, "Skin decals per frame", "Display", "iMaxSkinDecalsPerFrame", noSkinDecals
        ),
        option(.decals, "Decal limit", "Display", "uMaxDecals"),
        option(.decals, "Skin decal limit", "Display", "uMaxSkinDecals", noSkinDecals)
    ]

    /// Store rows for every option. A toggle stores 0 or 1; a number keeps the INI value.
    static var definitions: [PlayerSettingDefinition] {
        all.map { option in
            PlayerSettingDefinition(
                id: option.id, group: .opensky,
                kind: option.isToggle ? .toggle : .slider(range: 0 ... 10_000_000, step: 1),
                title: option.title, defaultValue: defaultValue(option),
                isApplied: option.unavailableReason == nil
            )
        }
    }

    /// Before the install's INI fills them in: OpenSky's own terrain fallback, else 0.
    private static func defaultValue(_ option: GraphicsOption) -> Double {
        let fallback = TerrainLODConfiguration.fallback
        return switch option.key {
        case "fBlockLevel0Distance": Double(fallback.level0Distance)
        case "fBlockLevel1Distance": Double(fallback.level1Distance)
        case "fBlockMaximumDistance": Double(fallback.maximumDistance)
        case "fTreeLoadDistance": Double(fallback.treeLoadDistance)
        case "bDecals": 1
        case "uMaxDecals": 100
        default: 0
        }
    }

    /// The value `file` gives `option`, as the store keeps it.
    public static func value(_ option: GraphicsOption, in file: INIFile) -> Double? {
        parse(file.string(section: option.section, key: option.key), option)
    }

    /// The highest-priority value of the layered INI files.
    public static func value(_ option: GraphicsOption, in ini: INISettings) -> Double? {
        parse(ini.string(section: option.section, key: option.key)?.value, option)
    }

    private static func parse(_ raw: String?, _ option: GraphicsOption) -> Double? {
        guard let raw, let number = Double(raw), number.isFinite else { return nil }
        return option.isToggle ? (number == 0 ? 0 : 1) : number
    }
}
