// The one place that answers "what is in this quest alias now?". A value type,
// so a condition on a cell build queue reads a snapshot. A VMAD property names an
// alias by number and a CIS1/CIS2 override by name, so there are two lookups.
// See docs/engine/quest-state.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated public struct QuestAliasResolution: Sendable {
    private let defaults: QuestStore
    private let tables: [ReferenceKey: QuestAliasState]

    public static let empty = QuestAliasResolution(defaults: .empty, tables: [:])

    public init(defaults: QuestStore?, tables: [ReferenceKey: QuestAliasState] = [:]) {
        self.defaults = defaults ?? .empty
        self.tables = tables
    }

    /// Resolution over a snapshot's alias components, for a consumer running
    /// off the main actor where the live store is unreachable.
    public init(defaults: QuestStore?, snapshot: WorldStateSnapshot) {
        var tables: [ReferenceKey: QuestAliasState] = [:]
        for entry in snapshot.entries {
            guard let state = entry.delta.component(QuestAliasState.self) else { continue }
            tables[entry.key] = state
        }
        self.init(defaults: defaults, tables: tables)
    }

    /// Filled table of the quest `id` names, empty when the quest defines
    /// aliases nothing has filled, and nil when no quest is named at all.
    public func table(for id: FormID) -> QuestAliasState? {
        guard defaults.quest(id) != nil else { return nil }
        guard let key = defaults.key(for: id) else { return .empty }
        return tables[key] ?? .empty
    }

    /// Reference filling one alias by number, or nil when it is empty.
    public func reference(alias aliasID: UInt32, in id: FormID) -> ReferenceKey? {
        table(for: id)?.reference(forAlias: aliasID)
    }

    /// Location filling one alias by number, or nil when it is empty.
    public func location(alias aliasID: UInt32, in id: FormID) -> ResolvedFormID? {
        table(for: id)?.location(forAlias: aliasID)
    }

    /// Alias ID one authored alias name stands for on the quest `id` names.
    ///
    /// Name matching is case-insensitive for the reason editor-ID lookup is:
    /// an alias name is written by hand into a CIS1 string and into a script,
    /// and the Creation Kit has never treated those as case-sensitive.
    public func aliasID(named name: String, in id: FormID) -> UInt32? {
        guard let quest = defaults.quest(id) else { return nil }
        let wanted = name.lowercased()
        return quest.aliases.first { $0.name?.lowercased() == wanted }?.id
    }

    /// Reference filling the alias `name` stands for, which is what a CIS1 or
    /// CIS2 override on a condition resolves to.
    public func reference(aliasNamed name: String, in id: FormID) -> ReferenceKey? {
        guard let aliasID = aliasID(named: name, in: id) else { return nil }
        return reference(alias: aliasID, in: id)
    }

    /// Quests with a filled table in this resolution.
    public var filledQuestCount: Int {
        tables.count { !$0.value.isEmpty }
    }

    /// Filled aliases across every quest.
    public var filledAliasCount: Int {
        tables.values.reduce(0) { $0 + $1.count }
    }
}

nonisolated extension QuestAliasResolution: ConditionResolution, ConditionAliasResolving {}

nonisolated extension ConditionContext {
    /// The one seam filled quest aliases come through. Separate
    /// from `quests` because the two answer different questions and a caller
    /// may legitimately have one and not the other.
    public var aliases: QuestAliasResolution {
        get { self[resolution: QuestAliasResolution.self] }
        set {
            self[resolution: QuestAliasResolution.self] = newValue
            aliasResolver = newValue
        }
    }
}
