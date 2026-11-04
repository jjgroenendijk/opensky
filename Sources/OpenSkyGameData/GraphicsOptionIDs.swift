// Store ids of the base game's graphics options that the engine reads. Each id is
// `graphics.` and the INI key, as `GraphicsOption.id` builds it.

nonisolated extension PlayerSettingID {
    public static let shadowDistance = Self("graphics.fShadowDistance")
    public static let shadowMapResolution = Self("graphics.iShadowMapResolution")
    public static let fadeActors = Self("graphics.fLODFadeOutMultActors")
    public static let fadeItems = Self("graphics.fLODFadeOutMultItems")
    public static let fadeObjects = Self("graphics.fLODFadeOutMultObjects")
    public static let grassFadeStart = Self("graphics.fGrassStartFadeDistance")
    public static let meshLODLevel1 = Self("graphics.fMeshLODLevel1FadeDist")
    public static let meshLODLevel2 = Self("graphics.fMeshLODLevel2FadeDist")
    public static let decalsPerFrame = Self("graphics.iMaxDecalsPerFrame")
    public static let precipitationOcclusion = Self("graphics.bUsePrecipitationOcclusion")
    public static let focusShadows = Self("graphics.iNumFocusShadow")
    public static let snowSparkles = Self("graphics.bToggleSparkles")
    public static let ambientOcclusion = Self("graphics.bSAOEnable")
    public static let volumetricLight = Self("graphics.bVolumetricLightingEnable")
    public static let depthOfField = Self("graphics.bDoDepthOfField")
    public static let lensFlare = Self("graphics.bLensFlare")
    public static let fxaa = Self("graphics.bFXAAEnabled")
    public static let temporalAntiAliasing = Self("graphics.bUseTAA")
    public static let highDynamicRangeTarget = Self("graphics.bUse64bitsHDRRenderTarget")
    public static let volumetricQuality = Self("graphics.iVolumetricLightingQuality")
}
