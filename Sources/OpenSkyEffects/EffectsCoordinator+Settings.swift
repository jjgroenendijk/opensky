// The player settings the effects follow: the game's decal options and
// OpenSky's impact-model switch.

import OpenSkyGameData
import OpenSkyRendering

extension EffectsCoordinator {
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        impactModelsEnabled = store.bool(.impactEffects)
        decalsEnabled = store.bool(.decals)
        let limit = store.value(.decalLimit)
        decalLimit = limit.isFinite && limit > 0 ? Int(min(limit, 10000)) : DecalRuntime
            .defaultLimit
    }
}
