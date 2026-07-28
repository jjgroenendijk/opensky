// Cross-plugin GMST index. Plugins are visited from lowest to highest
// priority; a later valid record with the same EDID replaces the earlier one.
// Deleted or malformed records do not erase the last valid value.

import Foundation
import OSLog

nonisolated struct ResolvedGameSetting: Equatable {
    let setting: GameSetting
    let sourcePlugin: String
}

nonisolated struct GameSettingStore {
    private(set) var values: [String: ResolvedGameSetting] = [:]

    init(plugins: [(name: String, file: ESMFile)]) {
        for plugin in plugins {
            add(pluginName: plugin.name, file: plugin.file)
        }
    }

    func setting(editorID: String) -> ResolvedGameSetting? {
        values[editorID.lowercased()]
    }

    private mutating func add(pluginName: String, file: ESMFile) {
        guard let group = file.topGroup(of: "GMST") else { return }
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        guard let children = try? group.children() else { return }
        for case let .record(record) in children where !record.isDeleted {
            guard let setting = try? GameSetting(record: record, localized: localized) else {
                continue
            }
            values[setting.editorID.lowercased()] = ResolvedGameSetting(
                setting: setting,
                sourcePlugin: pluginName
            )
        }
    }
}

nonisolated enum GameSettingLoader {
    private static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "GMST"
    )

    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> GameSettingStore {
        let entries = PluginLoadOrder.resolve(root: root)
        let plugins = entries.compactMap { entry -> (name: String, file: ESMFile)? in
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
        return GameSettingStore(plugins: plugins)
    }
}
