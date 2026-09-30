// Cross-plugin GMST index. Plugins are visited from lowest to highest
// priority; a later valid record with the same EDID replaces the earlier one.
// Deleted or malformed records do not erase the last valid value.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedGameSetting: Equatable, Sendable {
    public let setting: GameSetting
    public let sourcePlugin: String
}

nonisolated public struct GameSettingStore: Sendable {
    public private(set) var values: [String: ResolvedGameSetting] = [:]
    public private(set) var skippedRecords = SkippedRecords()

    public init(plugins: [(name: String, file: ESMFile)]) {
        for plugin in plugins {
            add(pluginName: plugin.name, file: plugin.file)
        }
    }

    public func setting(editorID: String) -> ResolvedGameSetting? {
        values[editorID.lowercased()]
    }

    private mutating func add(pluginName: String, file: ESMFile) {
        guard let group = file.topGroup(of: "GMST") else { return }
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        guard let children = try? group.children() else { return }
        for case let .record(record) in children where !record.isDeleted {
            guard
                let setting = skippedRecords.decode(
                    record,
                    using: { try GameSetting(record: $0, localized: localized) }
                )
            else { continue }
            values[setting.editorID.lowercased()] = ResolvedGameSetting(
                setting: setting,
                sourcePlugin: pluginName
            )
        }
    }
}

nonisolated public enum GameSettingLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> GameSettingStore {
        GameSettingStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
