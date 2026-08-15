// Load-order-wide SHOU and WOOP lookup above RecordIndex, in the shape
// `SpellStore` and `KeywordStore` already use.
//
// The two record types live in one store because a word of power is only ever
// reached through a shout: WOOP carries the text, SHOU carries the pairing
// between a word and the spell it casts, and nothing wants one without being
// able to reach the other. Each shout's SNAM run is joined against the word
// index and against `SpellStore` at construction, so an inspector prints names
// rather than raw links without redoing the resolution.
//
// Decode only. Shout casting, cooldowns, word unlocking and dragon souls are
// deliberately absent this milestone.

import Foundation

nonisolated struct ResolvedWordOfPower: Equatable {
    let id: ResolvedFormID
    let word: WordOfPower
    let sourcePlugin: String

    var editorID: String? {
        word.editorID
    }

    var displayName: String {
        switch word.name {
        case let .inline(value): value
        case let .tableID(tableID): word.editorID ?? "string #\(tableID)"
        case nil: word.editorID ?? id.description
        }
    }
}

/// One SNAM entry with both of its links chased.
nonisolated struct ResolvedShoutWord {
    let entry: Shout.Word
    let word: ResolvedWordOfPower?
    let spell: ResolvedSpell?

    var wordName: String {
        guard let entry = entry.word else { return "NULL" }
        return word?.displayName ?? "[UNRESOLVED] \(entry)"
    }

    var spellName: String {
        guard let entry = entry.spell else { return "NULL" }
        return spell?.displayName ?? "[UNRESOLVED] \(entry)"
    }
}

nonisolated struct ResolvedShout {
    let id: ResolvedFormID
    let shout: Shout
    let sourcePlugin: String
    let words: [ResolvedShoutWord]

    var editorID: String? {
        shout.editorID
    }

    var displayName: String {
        switch shout.name {
        case let .inline(value): value
        case let .tableID(tableID): shout.editorID ?? "string #\(tableID)"
        case nil: shout.editorID ?? id.description
        }
    }
}

nonisolated struct ShoutStore {
    private let index: RecordIndex
    /// Every winning SHOU identity in the load order.
    private(set) var shouts: [ResolvedFormID: ResolvedShout] = [:]
    /// Every winning WOOP identity in the load order.
    private(set) var words: [ResolvedFormID: ResolvedWordOfPower] = [:]
    private var shoutsByEditorID: [String: ResolvedShout] = [:]
    private var wordsByEditorID: [String: ResolvedWordOfPower] = [:]

    init(index: RecordIndex, spells: SpellStore) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        // Words first: a shout joins against them as it is built.
        for id in orderedIDs where index.records[id]?.record.type == "WOOP" {
            guard
                case let .decoded(word, sourcePlugin) = index.decodeIndexed(id, using: Self.word)
            else { continue }
            let resolved = ResolvedWordOfPower(id: id, word: word, sourcePlugin: sourcePlugin)
            words[id] = resolved
            if let editorID = word.editorID {
                wordsByEditorID[editorID.lowercased()] = resolved
            }
        }
        for id in orderedIDs where index.records[id]?.record.type == "SHOU" {
            guard
                case let .decoded(shout, sourcePlugin) = index.decodeIndexed(id, using: Self.shout)
            else { continue }
            let resolved = ResolvedShout(
                id: id,
                shout: shout,
                sourcePlugin: sourcePlugin,
                words: join(shout: shout, sourcePlugin: sourcePlugin, spells: spells)
            )
            shouts[id] = resolved
            if let editorID = shout.editorID {
                shoutsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    init(index: RecordIndex) {
        self.init(index: index, spells: SpellStore(index: index))
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(
            index: RecordIndex(
                plugins: plugins,
                recordTypes: ["MGEF", "SPEL", "SCRL", "SHOU", "WOOP"]
            )
        )
    }

    func shout(_ id: ResolvedFormID) -> ResolvedShout? {
        shouts[id] ?? shouts.first { key, _ in matches(key, id) }?.value
    }

    func shout(editorID: String) -> ResolvedShout? {
        shoutsByEditorID[editorID.lowercased()]
    }

    func word(_ id: ResolvedFormID) -> ResolvedWordOfPower? {
        words[id] ?? words.first { key, _ in matches(key, id) }?.value
    }

    func word(editorID: String) -> ResolvedWordOfPower? {
        wordsByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    func resolveWord(_ id: FormID, fromPlugin pluginName: String) -> ResolvedWordOfPower? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return word(resolvedID)
    }

    /// Joins one shout's SNAM run against the word index and the spell store.
    /// Exposed so the text dump, which decodes the record in front of it, gets
    /// the same names the store holds.
    func join(
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

nonisolated enum ShoutStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> ShoutStore {
        ShoutStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
