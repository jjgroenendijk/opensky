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
        case let .tableID(tableID), let .pluginTableID(tableID, _):
            word.editorID ?? "string #\(tableID)"
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
        case let .tableID(tableID), let .pluginTableID(tableID, _):
            shout.editorID ?? "string #\(tableID)"
        case nil: shout.editorID ?? id.description
        }
    }
}

nonisolated public struct ShoutStore: Sendable {
    private let index: RecordIndex
    private let shoutTable: ResolvedRecordTable<ResolvedShout>
    private let wordTable: ResolvedRecordTable<ResolvedWordOfPower>

    /// Every winning SHOU identity in the load order.
    public var shouts: [ResolvedFormID: ResolvedShout] {
        shoutTable.values
    }

    /// Every winning WOOP identity in the load order.
    public var words: [ResolvedFormID: ResolvedWordOfPower] {
        wordTable.values
    }

    public var skippedRecords: SkippedRecords {
        shoutTable.skipped.merging(wordTable.skipped)
    }

    public init(index: RecordIndex, spells: SpellStore) {
        self.index = index
        // Words first: a shout joins against them as it is built.
        let words = ResolvedRecordTable(
            index: index,
            types: ["WOOP"],
            decode: Self.word,
            editorID: \.editorID,
            resolve: { id, word, _ in ResolvedWordOfPower(id: id, word: word) }
        )
        wordTable = words
        shoutTable = ResolvedRecordTable(
            index: index,
            types: ["SHOU"],
            decode: Self.shout,
            editorID: \.editorID,
            resolve: { id, shout, sourcePlugin in
                ResolvedShout(
                    id: id,
                    shout: shout,
                    words: Self.join(
                        shout: shout,
                        sourcePlugin: sourcePlugin,
                        spells: spells,
                        words: words,
                        index: index
                    )
                )
            }
        )
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
        shoutTable.value(editorID: editorID)
    }

    /// Joins one shout's SNAM run against the word index and the spell store.
    /// Public so the text dump gets the same names the store holds.
    public func join(
        shout: Shout,
        sourcePlugin: String,
        spells: SpellStore
    ) -> [ResolvedShoutWord] {
        Self.join(
            shout: shout,
            sourcePlugin: sourcePlugin,
            spells: spells,
            words: wordTable,
            index: index
        )
    }

    private static func join(
        shout: Shout,
        sourcePlugin: String,
        spells: SpellStore,
        words: ResolvedRecordTable<ResolvedWordOfPower>,
        index: RecordIndex
    ) -> [ResolvedShoutWord] {
        shout.words.map { entry in
            ResolvedShoutWord(
                entry: entry,
                word: index.resolvedID(entry.word, fromPlugin: sourcePlugin)
                    .flatMap { words.value($0) },
                spell: entry.spell.flatMap { spells.resolve($0, fromPlugin: sourcePlugin) }
            )
        }
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
