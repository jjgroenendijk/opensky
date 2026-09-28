// Loads every active plugin's MOVT records from a data root. The decoder lives
// with the parsers in OpenSkyFormats; finding the active plugins is engine work.

import OpenSkyFormats

nonisolated enum MovementTypeLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> MovementTypeStore {
        MovementTypeStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
