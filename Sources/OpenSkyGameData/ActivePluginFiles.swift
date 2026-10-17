// Opens every active plugin once, in load order, for index builders such as
// `GameSettingStore` and `MovementTypeStore` (later plugin wins). A plugin that
// will not open is logged and skipped, so one bad mod does not cost every setting.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum ActivePluginFiles: Sendable {
    private static let logger = EngineLogger(
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

/// The active plugins, opened once and numbered as the game numbers forms. Engine
/// code and tools read records through this, so no reader sees one plugin alone.
nonisolated public struct ActiveLoadOrder: Sendable {
    /// `Skyrim.esm`, the master every other plugin builds on.
    public let baseFile: ESMFile
    public let plugins: LoadOrderPlugins

    public init(baseFile: ESMFile, plugins: LoadOrderPlugins) {
        self.baseFile = baseFile
        self.plugins = plugins
    }

    /// Throws when `Skyrim.esm` cannot be read; another plugin that will not
    /// open is logged and skipped.
    public static func open(root: GameDataRoot) throws -> ActiveLoadOrder {
        try ActiveLoadOrder(root: root, baseFile: openBaseFile(root: root))
    }

    /// The first half of `open`, for a loader that reports the two halves apart.
    public static func openBaseFile(root: GameDataRoot) throws -> ESMFile {
        try ESMFile(url: root.dataURL.appending(path: baseFileName))
    }

    /// Opens the other active plugins beside an already-open `Skyrim.esm`.
    public init(root: GameDataRoot, baseFile: ESMFile) {
        self.init(
            baseFile: baseFile,
            plugins: LoadOrderPlugins(ActivePluginFiles.load(root: root, baseFile: baseFile))
        )
    }

    public static let baseFileName = "Skyrim.esm"

    public var files: [(name: String, file: ESMFile)] {
        plugins.files
    }
}
