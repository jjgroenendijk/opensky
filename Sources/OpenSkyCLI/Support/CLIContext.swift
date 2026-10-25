// Shared command plumbing: data-root resolution and engine entry points
// (VFS, Skyrim.esm). --data-root goes through GameDataLocator's validation, so
// both accepted root shapes and the fail-loud behavior match the app.

import Foundation
import OpenSkyGameData

struct CLIContext {
    let root: GameDataRoot

    /// Resolves the game data root: --data-root override when given, else
    /// the locator chain (env var, user default, Steam path). Missing or
    /// invalid -> the locator's typed error (clear message, exit 1).
    static func resolve(dataRootOverride: String?) throws -> CLIContext {
        if let dataRootOverride {
            return try CLIContext(root: GameDataLocator.locate(commandLinePath: dataRootOverride))
        }
        return try CLIContext(root: GameDataLocator.locate())
    }

    func makeFileSystem() -> VirtualFileSystem {
        VirtualFileSystem(root: root)
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
