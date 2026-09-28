// Loads every active plugin's MOVT records from a data root. The decoder lives
// with the parsers in OpenSkyFormatsESM; finding the active plugins is engine work.

import OpenSkyFormatsESM

nonisolated public enum MovementTypeLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> MovementTypeStore {
        MovementTypeStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
