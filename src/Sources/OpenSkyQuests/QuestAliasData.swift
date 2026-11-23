// What a reference gains and loses as it enters and leaves a quest's reference
// aliases: factions and spells while it is in, items once on entering
// (<https://ck.uesp.net/wiki/Quest_Alias_Tab>). See docs/engine/quest-state.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyQuestsInterface

/// One reference entering or leaving one alias, with the alias data that goes with it.
nonisolated public struct QuestAliasDataChange: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let item: ResolvedFormID
        public let count: Int32
    }

    public let reference: ReferenceKey
    /// True on entering the alias, false on leaving it.
    public let entered: Bool
    public let factions: [ResolvedFormID]
    public let spells: [ResolvedFormID]
    /// Only on entering: the items stay when the reference leaves.
    public let items: [Item]
}

nonisolated public enum QuestAliasData {
    /// Leaves come before entries, so an alias forced from one reference to another
    /// takes the faction from the first before the second joins.
    public static func changes(
        aliases: [Quest.Alias],
        resolver: FormIDResolver,
        old: QuestAliasState,
        new: QuestAliasState
    ) -> [QuestAliasDataChange] {
        var leaves: [QuestAliasDataChange] = []
        var entries: [QuestAliasDataChange] = []
        for alias in aliases where carriesData(alias) {
            let before = old.reference(forAlias: alias.id)
            let after = new.reference(forAlias: alias.id)
            guard before != after else { continue }
            if let before {
                leaves.append(change(alias, reference: before, entered: false, resolver))
            }
            if let after {
                entries.append(change(alias, reference: after, entered: true, resolver))
            }
        }
        return leaves + entries
    }

    private static func carriesData(_ alias: Quest.Alias) -> Bool {
        !alias.factions.isEmpty || !alias.spells.isEmpty || !alias.items.isEmpty
    }

    private static func change(
        _ alias: Quest.Alias, reference: ReferenceKey, entered: Bool, _ resolver: FormIDResolver
    ) -> QuestAliasDataChange {
        let items = entered ? alias.items.compactMap { entry in
            resolver.resolve(entry.item).map {
                QuestAliasDataChange.Item(item: $0, count: entry.count)
            }
        } : []
        return QuestAliasDataChange(
            reference: reference,
            entered: entered,
            factions: alias.factions.compactMap(resolver.resolve),
            spells: alias.spells.compactMap(resolver.resolve),
            items: items
        )
    }
}
