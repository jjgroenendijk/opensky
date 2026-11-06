// The player settings the effects follow: the game's decal and skin decal options
// and OpenSky's impact-model switch.

import OpenSkyGameData
import OpenSkyRenderCore

extension EffectsCoordinator {
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        impactModelsEnabled = store.bool(.impactEffects)
        screenBloodEnabled = store.bool(.screenBlood)
        healthCues.pulseEnabled = store.bool(.lowHealthPulse)
        decalsEnabled = store.bool(.decals)
        let limit = store.value(.decalLimit)
        decalLimit = limit.isFinite && limit > 0 ? Int(min(limit, 10000)) : DecalRuntime
            .defaultLimit
        let perFrame = store.value(.decalsPerFrame)
        decals.perFrameLimit = perFrame.isFinite && perFrame > 0 ? Int(min(perFrame, 10000)) : 0
        skinDecalsEnabled = store.bool(.decals) && store.bool(.skinDecals)
        let skinLimit = store.value(.skinDecalLimit)
        skinDecals.decals.limit = skinLimit.isFinite && skinLimit > 0
            ? Int(min(skinLimit, 10000)) : SkinDecalRuntime.defaultLimit
        let skinPerFrame = store.value(.skinDecalsPerFrame)
        skinDecals.decals.perFrameLimit = skinPerFrame.isFinite && skinPerFrame > 0
            ? Int(min(skinPerFrame, 10000)) : 0
    }
}
