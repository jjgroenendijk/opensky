import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData

nonisolated public struct SessionStartReport: Equatable, Sendable {
    public var entries: [SessionStartEntry] = []
    /// Plugins in the load order with no `.seq` file.
    public var missingLists: [String] = []
    /// Plugins whose `.seq` file did not parse.
    public var brokenLists: [String] = []

    public static let empty = SessionStartReport()

    public init() {}

    var startedCount: Int {
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
        guard files.exists(path), let data = attempt({ try files.contents(forPath: path) }) else {
            return PluginQuestList(plugin: plugin, masters: masters, list: nil)
        }
        let list = Result { () throws(StartGameQuestListError) in
            try StartGameQuestList(data: data)
        }
        return PluginQuestList(plugin: plugin, masters: masters, list: list)
    }
}

nonisolated public struct SessionStartEntry: Equatable, Sendable {
    public let plugin: String
    public let quest: ResolvedFormID
    public let editorID: String?
    public let outcome: SessionStartOutcome

    public init(
        plugin: String,
        quest: ResolvedFormID,
        editorID: String?,
        outcome: SessionStartOutcome
    ) {
        self.plugin = plugin
        self.quest = quest
        self.editorID = editorID
        self.outcome = outcome
    }
}

nonisolated public enum SessionStartOutcome: Equatable, Sendable {
    case started
    /// Runtime state exists, from an earlier pass or a save, so nothing restarts it.
    case alreadyHasState
    /// The quest belongs to a plugin the quest store does not index.
    case notInQuestStore
    case startFailed(String)
}
