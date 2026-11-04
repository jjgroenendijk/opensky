// The player settings the effects follow: the game's decal options and
// OpenSky's impact-model switch.

import OpenSkyGameData
import OpenSkyRenderCore

extension EffectsCoordinator {
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        impactModelsEnabled = store.bool(.impactEffects)
        screenBloodEnabled = store.bool(.screenBlood)
        decalsEnabled = store.bool(.decals)
        let limit = store.value(.decalLimit)
        decalLimit = limit.isFinite && limit > 0 ? Int(min(limit, 10000)) : DecalRuntime
            .defaultLimit
        let perFrame = store.value(.decalsPerFrame)
        decals.perFrameLimit = perFrame.isFinite && perFrame > 0 ? Int(min(perFrame, 10000)) : 0
    }
}
