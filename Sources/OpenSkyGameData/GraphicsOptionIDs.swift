// Store ids of the base game's graphics options that the engine reads. Each id is
// `graphics.` and the INI key, as `GraphicsOption.id` builds it.

nonisolated extension PlayerSettingID {
    public static let shadowDistance = Self("graphics.fShadowDistance")
    public static let shadowMapResolution = Self("graphics.iShadowMapResolution")
}
