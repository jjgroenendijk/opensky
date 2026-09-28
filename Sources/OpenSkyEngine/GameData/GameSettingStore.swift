// Cross-plugin GMST index. Plugins are visited from lowest to highest
// priority; a later valid record with the same EDID replaces the earlier one.
// Deleted or malformed records do not erase the last valid value.

import Foundation

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
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> GameSettingStore {
        GameSettingStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
