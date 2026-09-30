// Load-order-wide SHOU and WOOP lookup above RecordIndex, like `SpellStore`. One
// store, because a word of power is only reached through a shout. Each shout's
// SNAM run is joined with the words and `SpellStore` at construction. Decode
// only: no casting, cooldowns, or word unlocking.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedWordOfPower: Equatable, Sendable {
    public let id: ResolvedFormID
    public let word: WordOfPower

    public var editorID: String? {
        word.editorID
    }

    public var displayName: String {
        switch word.name {
        case let .inline(value): value
        case let .tableID(tableID): word.editorID ?? "string #\(tableID)"
        case nil: word.editorID ?? id.description
        }
    }
}

/// One SNAM entry with both of its links chased.
nonisolated public struct ResolvedShoutWord: Sendable {
    public let entry: Shout.Word
    public let word: ResolvedWordOfPower?
    public let spell: ResolvedSpell?

    public var wordName: String {
        guard let entry = entry.word else { return "NULL" }
        return word?.displayName ?? "[UNRESOLVED] \(entry)"
    }

    public var spellName: String {
        guard let entry = entry.spell else { return "NULL" }
        return spell?.displayName ?? "[UNRESOLVED] \(entry)"
    }
}

nonisolated public struct ResolvedShout: Sendable {
    public let id: ResolvedFormID
    public let shout: Shout
    public let words: [ResolvedShoutWord]

    public var displayName: String {
        switch shout.name {
        case let .inline(value): value
        case let .tableID(tableID): shout.editorID ?? "string #\(tableID)"
        case nil: shout.editorID ?? id.description
        }
    }
}

nonisolated public struct ShoutStore: Sendable {
    private let index: RecordIndex
    /// Every winning SHOU identity in the load order.
    public private(set) var shouts: [ResolvedFormID: ResolvedShout] = [:]
    /// Every winning WOOP identity in the load order.
    public private(set) var words: [ResolvedFormID: ResolvedWordOfPower] = [:]
    private var shoutsByEditorID: [String: ResolvedShout] = [:]

    public init(index: RecordIndex, spells: SpellStore) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        // Words first: a shout joins against them as it is built.
        for id in orderedIDs where index.records[id]?.record.type == "WOOP" {
            guard
                case let .decoded(word, _) = index.decodeIndexed(id, using: Self.word)
            else { continue }
            words[id] = ResolvedWordOfPower(id: id, word: word)
        }
        for id in orderedIDs where index.records[id]?.record.type == "SHOU" {
            guard
                case let .decoded(shout, sourcePlugin) = index.decodeIndexed(id, using: Self.shout)
            else { continue }
            let resolved = ResolvedShout(
                id: id,
                shout: shout,
                words: join(shout: shout, sourcePlugin: sourcePlugin, spells: spells)
            )
            shouts[id] = resolved
            if let editorID = shout.editorID {
                shoutsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    public init(index: RecordIndex) {
        self.init(index: index, spells: SpellStore(index: index))
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(
            index: RecordIndex(
                plugins: plugins,
                recordTypes: ["MGEF", "SPEL", "SCRL", "SHOU", "WOOP"]
            )
        )
    }

    public func shout(editorID: String) -> ResolvedShout? {
        shoutsByEditorID[editorID.lowercased()]
    }

    public func word(_ id: ResolvedFormID) -> ResolvedWordOfPower? {
        words[id] ?? words.first { key, _ in matches(key, id) }?.value
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    public func resolveWord(_ id: FormID, fromPlugin pluginName: String) -> ResolvedWordOfPower? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return word(resolvedID)
    }

    /// Joins one shout's SNAM run against the word index and the spell store.
    /// Exposed so the text dump, which decodes the record in front of it, gets
    /// the same names the store holds.
    public func join(
        shout: Shout,
        sourcePlugin: String,
        spells: SpellStore
    ) -> [ResolvedShoutWord] {
        shout.words.map { entry in
            ResolvedShoutWord(
                entry: entry,
                word: entry.word.flatMap { resolveWord($0, fromPlugin: sourcePlugin) },
                spell: entry.spell.flatMap { spells.resolve($0, fromPlugin: sourcePlugin) }
            )
        }
    }

    private func matches(_ key: ResolvedFormID, _ id: ResolvedFormID) -> Bool {
        key.objectID == id.objectID
            && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
    }

    private static func shout(_ indexed: IndexedRecord) throws -> Shout {
        try Shout(record: indexed.record, localized: indexed.localized)
    }

    private static func word(_ indexed: IndexedRecord) throws -> WordOfPower {
        try WordOfPower(record: indexed.record, localized: indexed.localized)
    }
}

nonisolated public enum ShoutStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> ShoutStore {
        ShoutStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
