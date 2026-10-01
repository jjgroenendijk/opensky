// Opens every active plugin once, in load order, for index builders such as
// `GameSettingStore` and `MovementTypeStore` (later plugin wins). A plugin that
// will not open is logged and skipped, so one bad mod does not cost every setting.

import Foundation
import OpenSkyFormatsESM
import OSLog

nonisolated public enum ActivePluginFiles: Sendable {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Plugins"
    )

    /// Every active plugin, lowest priority first.
    ///
    /// - Parameter baseFile: an already-open `Skyrim.esm`, reused rather than
    ///   re-read when the load order names it.
    public static func load(
        root: GameDataRoot,
        baseFile: ESMFile? = nil
    ) -> [(name: String, file: ESMFile)] {
        PluginLoadOrder.resolve(root: root).entries.compactMap { entry in
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
