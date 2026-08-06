// Opening every active plugin once, in load order, for the index builders that
// need the whole load order rather than Skyrim.esm alone.
//
// `GameSettingStore` (GMST) and `MovementTypeStore` (MOVT) both walk the same
// list and both want the same override rule — later plugin wins — so the walk
// lives here instead of once per index. A plugin that will not open is logged
// and skipped: one unreadable mod must not cost the caller every setting in
// the game.

import Foundation
import OSLog

nonisolated enum ActivePluginFiles {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Plugins"
    )

    /// Every active plugin, lowest priority first.
    ///
    /// - Parameter baseFile: an already-open `Skyrim.esm`, reused rather than
    ///   re-read when the load order names it.
    static func load(
        root: GameDataRoot,
        baseFile: ESMFile? = nil
    ) -> [(name: String, file: ESMFile)] {
        PluginLoadOrder.resolve(root: root).compactMap { entry in
            if
                entry.name.caseInsensitiveCompare("Skyrim.esm") == .orderedSame,
                let baseFile
            {
                return (entry.name, baseFile)
            }
            do {
                return try (entry.name, ESMFile(url: entry.url))
            } catch {
                logger.error(
                    """
                    Cannot read active plugin \(entry.name, privacy: .public): \
                    \(String(describing: error), privacy: .public)
                    """
                )
                return nil
            }
        }
    }
}
