// The GPU features the player settings ask for. The launcher's Graphics page and the
// Rendering Performance panel write the same settings.

import OpenSkyGameData
import OpenSkyRendering

extension Renderer {
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        gpuCullingEnabled = store.bool(.gpuCulling)
    }
}
