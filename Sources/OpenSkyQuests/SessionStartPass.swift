// The session-start pass: each load-order plugin's `.seq` list names the quests
// a new game starts. A listed quest with no runtime state is started for real,
// so its aliases fill and its start-up stage runs. See docs/engine/story-manager.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

nonisolated public enum SessionStartOutcome: Equatable, Sendable {
    case started
    /// Runtime state exists, from an earlier pass or a save, so nothing restarts it.
    case alreadyHasState
    /// The quest belongs to a plugin the quest store does not index.
    case notInQuestStore
    case startFailed(String)
}

nonisolated public struct SessionStartEntry: Equatable, Sendable {
    public let plugin: String
    public let quest: ResolvedFormID
    public let editorID: String?
    public let outcome: SessionStartOutcome
}

nonisolated public struct SessionStartReport: Equatable, Sendable {
    public var entries: [SessionStartEntry] = []
    /// Plugins in the load order with no `.seq` file.
    public var missingLists: [String] = []
    /// Plugins whose `.seq` file did not parse.
    public var brokenLists: [String] = []

    public static let empty = SessionStartReport()

    public init() {}

    public var startedCount: Int {
        entries.count { $0.outcome == .started }
    }
}

/// One plugin's list, read from the virtual file system.
nonisolated public struct PluginQuestList: Sendable {
    public let plugin: String
    public let masters: [String]
    public let list: Result<StartGameQuestList, StartGameQuestListError>?

    public init(
        plugin: String,
        masters: [String],
        list: Result<StartGameQuestList, StartGameQuestListError>?
    ) {
        self.plugin = plugin
        self.masters = masters
        self.list = list
    }

    /// Reads `seq\<plugin>.seq`. Nil list: the plugin has none.
    public static func load(
        plugin: String,
        masters: [String],
        files: any GameFileSource
    ) -> PluginQuestList {
        let path = StartGameQuestList.path(forPlugin: plugin)
        guard files.exists(path), let data = try? files.contents(forPath: path) else {
            return PluginQuestList(plugin: plugin, masters: masters, list: nil)
        }
        let list = Result { () throws(StartGameQuestListError) in
            try StartGameQuestList(data: data)
        }
        return PluginQuestList(plugin: plugin, masters: masters, list: list)
    }
}

@MainActor
extension QuestRuntime {
    /// Starts every listed quest that has no runtime state yet. Running it twice
    /// starts nothing the second time.
    public func runSessionStart(
        lists: [PluginQuestList],
        starter: (any QuestStarting)?
    ) -> SessionStartReport {
        var report = SessionStartReport()
        for plugin in lists {
            switch plugin.list {
            case nil:
                report.missingLists.append(plugin.plugin)
            case .failure:
                report.brokenLists.append(plugin.plugin)
            case let .success(list):
                let resolver = FormIDResolver(pluginName: plugin.plugin, masters: plugin.masters)
                for raw in list.quests {
                    guard let resolved = resolver.resolve(raw) else { continue }
                    report.entries.append(sessionStart(
                        resolved,
                        plugin: plugin.plugin,
                        starter: starter
                    ))
                }
            }
        }
        return report
    }

    private func sessionStart(
        _ resolved: ResolvedFormID,
        plugin: String,
        starter: (any QuestStarting)?
    ) -> SessionStartEntry {
        guard
            let id = quests.resolver.localFormID(of: resolved),
            let quest = quests.quest(id)
        else {
            return SessionStartEntry(
                plugin: plugin, quest: resolved, editorID: nil, outcome: .notInQuestStore
            )
        }
        let outcome: SessionStartOutcome
        if hasRuntimeState(id) {
            outcome = .alreadyHasState
        } else {
            do {
                if let starter {
                    try starter.startQuest(id, event: nil)
                } else {
                    try startQuestWithStartUpStage(id, event: nil)
                }
                outcome = .started
            } catch {
                outcome = .startFailed(String(describing: error))
            }
        }
        return SessionStartEntry(
            plugin: plugin, quest: resolved, editorID: quest.editorID, outcome: outcome
        )
    }
}
