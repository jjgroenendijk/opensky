// The GPU features the player settings ask for. The launcher's Graphics page and the
// Rendering Performance panel write the same settings.

import OpenSkyGameData
import OpenSkyRendering

extension Renderer {
    public func applyGraphicsSettings(_ store: PlayerSettingsStore) {
        gpuCullingEnabled = store.bool(.gpuCulling)
        textureStreaming.enabled = store.bool(.textureStreaming)
        textureStreaming.budgetBytes = Self.textureBudgetBytes(store: store)
    }

    public static func textureBudgetBytes(store: PlayerSettingsStore) -> Int {
        let options = PlayerSettingsCatalog.textureBudgetOptions
        let index = min(max(Int(store.value(.textureBudget)), 0), options.count - 1)
        return options[index] << 20
    }

    /// Streams the textures of the cells `runner` builds from now on.
    public func attachTextureStreaming(to runner: any CellBuildRunning) {
        guard let runner = runner as? SerialCellBuildRunner else { return }
        runner.attachTextureStreaming(textureStreaming.mailbox)
        textureStreaming.reader = runner
    }
}
