// Shared command plumbing: data-root resolution and engine entry points
// (VFS, Skyrim.esm). --data-root reuses GameDataLocator validation by
// injecting the override as the environment source, so both accepted root
// shapes and the fail-loud behavior match the app exactly.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

struct CLIContext {
    let root: GameDataRoot

    /// Resolves the game data root: --data-root override when given, else
    /// the locator chain (env var, user default, Steam path). Missing or
    /// invalid -> the locator's typed error (clear message, exit 1).
    static func resolve(dataRootOverride: String?) throws -> CLIContext {
        let environment: [String: String] = if let dataRootOverride {
            [GameDataLocator.environmentKey: dataRootOverride]
        } else {
            ProcessInfo.processInfo.environment
        }
        return try CLIContext(root: GameDataLocator.locate(environment: environment))
    }

    func makeFileSystem() -> VirtualFileSystem {
        VirtualFileSystem(root: root)
    }

    func makeTerrainLODConfigurationStore() -> TerrainLODConfigurationStore {
        TerrainLODConfigurationStore(snapshot: TerrainLODSettings.load(
            root: root,
            settings: PlayerSettingsFile.savedData()
        ))
    }

    /// File name of the base plugin, which is what a record link inside it
    /// resolves against in a load-order-wide store.
    var skyrimESMName: String {
        ActiveLoadOrder.baseFileName
    }

    /// Every active plugin. Commands read records through this, never one plugin alone.
    func loadOrder() throws -> ActiveLoadOrder {
        do {
            return try ActiveLoadOrder.open(root: root)
        } catch {
            let url = root.dataURL.appending(path: ActiveLoadOrder.baseFileName)
            throw CLIError.failure(
                "cannot read \(url.path(percentEncoded: false)): \(String(describing: error))"
            )
        }
    }
}
