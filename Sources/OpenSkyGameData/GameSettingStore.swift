// Cross-plugin GMST index. Plugins are visited from lowest to highest
// priority; a later valid record with the same EDID replaces the earlier one.
// Deleted or malformed records do not erase the last valid value.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import Synchronization

nonisolated public struct ResolvedGameSetting: Equatable, Sendable {
    public let setting: GameSetting
    public let sourcePlugin: String
}

nonisolated public struct GameSettingStore: Sendable {
    public private(set) var values: [String: ResolvedGameSetting] = [:]
    public private(set) var skippedRecords = SkippedRecords()
    /// Notes every editor ID a reader asks for, so `openskycli gaps` can list the
    /// settings no code reads. Nil in play.
    public var readLog: GameSettingReadLog?

    public init(plugins: [(name: String, file: ESMFile)]) {
        for plugin in plugins {
            add(pluginName: plugin.name, file: plugin.file)
        }
    }

    public func setting(editorID: String) -> ResolvedGameSetting? {
        readLog?.note(editorID)
        return values[editorID.lowercased()]
    }

    private mutating func add(pluginName: String, file: ESMFile) {
        guard let group = file.topGroup(of: "GMST") else { return }
        let localized = file.isLocalized
        for case let .record(record) in skippedRecords.children(of: group) where !record.isDeleted {
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

/// Editor IDs readers asked a `GameSettingStore` for, lowercased.
nonisolated public final class GameSettingReadLog: Sendable {
    private let names = Mutex<Set<String>>([])

    public init() {}

    public var editorIDs: Set<String> {
        names.withLock(\.self)
    }

    func note(_ editorID: String) {
        names.withLock { _ = $0.insert(editorID.lowercased()) }
    }
}

nonisolated public enum GameSettingLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> GameSettingStore {
        GameSettingStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
