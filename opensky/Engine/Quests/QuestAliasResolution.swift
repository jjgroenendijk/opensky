// The one place anything asks "what is in this quest alias right now?" (issue
// #183), mirroring `QuestResolution` and `GlobalResolution`.
//
// A value type carrying the plugin index plus this session's filled tables, so
// a consumer running off the main actor — a condition evaluated on a cell build
// queue — reads alias fills from a snapshot exactly as the main actor reads
// them from the live store. Nothing downstream reaches past this into
// `WorldStateStore`.
//
// Two lookups, because two different callers name an alias two different ways:
// a VMAD property and a `questAlias` run-on carry an alias *number*, while a
// CIS1/CIS2 condition override carries the authored alias *name*. Both end at
// the same table; only the way in differs.
//
// Documented in docs/engine/runtime-state.md.

import Foundation

nonisolated struct QuestAliasResolution: Sendable {
    private let defaults: QuestStore
    private let tables: [ReferenceKey: QuestAliasState]

    static let empty = QuestAliasResolution(defaults: .empty, tables: [:])

    init(defaults: QuestStore?, tables: [ReferenceKey: QuestAliasState] = [:]) {
        self.defaults = defaults ?? .empty
        self.tables = tables
    }

    /// Resolution over a snapshot's alias components, for a consumer running
    /// off the main actor where the live store is unreachable.
    init(defaults: QuestStore?, snapshot: WorldStateSnapshot) {
        var tables: [ReferenceKey: QuestAliasState] = [:]
        for entry in snapshot.entries {
            guard let state = entry.delta.component(QuestAliasState.self) else { continue }
            tables[entry.key] = state
        }
        self.init(defaults: defaults, tables: tables)
    }

    /// Filled table of the quest `id` names, empty when the quest defines
    /// aliases nothing has filled, and nil when no quest is named at all.
    func table(for id: FormID) -> QuestAliasState? {
        guard defaults.quest(id) != nil else { return nil }
        guard let key = defaults.key(for: id) else { return .empty }
        return tables[key] ?? .empty
    }

    /// Reference filling one alias by number, or nil when it is empty.
    func reference(alias aliasID: UInt32, in id: FormID) -> ReferenceKey? {
        table(for: id)?.reference(forAlias: aliasID)
    }

    /// Alias ID one authored alias name stands for on the quest `id` names.
    ///
    /// Name matching is case-insensitive for the reason editor-ID lookup is:
    /// an alias name is written by hand into a CIS1 string and into a script,
    /// and the Creation Kit has never treated those as case-sensitive.
    func aliasID(named name: String, in id: FormID) -> UInt32? {
        guard let quest = defaults.quest(id) else { return nil }
        let wanted = name.lowercased()
        return quest.aliases.first { $0.name?.lowercased() == wanted }?.id
    }

    /// Reference filling the alias `name` stands for, which is what a CIS1 or
    /// CIS2 override on a condition resolves to.
    func reference(aliasNamed name: String, in id: FormID) -> ReferenceKey? {
        guard let aliasID = aliasID(named: name, in: id) else { return nil }
        return reference(alias: aliasID, in: id)
    }

    /// Quests with a filled table in this resolution.
    var filledQuestCount: Int {
        tables.count { !$0.value.isEmpty }
    }

    /// Filled aliases across every quest.
    var filledAliasCount: Int {
        tables.values.reduce(0) { $0 + $1.count }
    }
}
