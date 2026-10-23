// The persisted settings and the readout of `ActorGraphCoordinator`.

import OpenSkyGameData

extension ActorGraphCoordinator {
    /// Reads the switch and the cutoff from `store`.
    public func load(settings store: PlayerSettingsStore) {
        isEnabled = store.bool(.actorGraphs)
        cutoff = ActorGraphCutoff(
            fullRateDistance: Float(store.value(.actorGraphFullRateDistance)),
            maximumDistance: Float(store.value(.actorGraphDistance))
        )
    }
}
