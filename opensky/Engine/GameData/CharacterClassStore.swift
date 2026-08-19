// Load-order-wide CLAS lookup above `RecordIndex` (issue #496, roadmap item
// 20.3), in the shape `MagicEffectStore` and `PerkStore` already use: winning
// record per identity, editor-id lookup, and links resolved relative to the
// plugin that carries them.
//
// It replaces `CharacterClassIndex`, which was a plain `[UInt32: CharacterClass]`
// map built from one file — the last record store in the engine not built on
// `RecordIndex`, and therefore the last one with no cross-plugin override
// handling at all. A patch plugin that rebalances `EncBandit`'s class was
// silently ignored: the index keyed raw FormIDs inside one file, so a later
// plugin's CLAS could not win over an earlier one's, and it could not even be
// seen unless it lived in the same file as the actors.
//
// What a class contributes is documented with the record
// (`opensky/Engine/Formats/ESM/Records/CharacterClass.swift`) and with the
// derivation it feeds (docs/engine/actor-values.md).

import Foundation

/// One CLAS record under its load-order identity.
nonisolated struct ResolvedCharacterClass: Equatable {
    let id: ResolvedFormID
    let characterClass: CharacterClass
    let sourcePlugin: String

    var editorID: String? {
        characterClass.editorID
    }

    var displayName: String {
        switch characterClass.name {
        case let .inline(value): value
        case .tableID: characterClass.editorID ?? id.description
        case nil: characterClass.editorID ?? id.description
        }
    }
}

nonisolated struct CharacterClassStore: Equatable {
    private(set) var classes: [ResolvedFormID: ResolvedCharacterClass] = [:]
    private var classesByEditorID: [String: ResolvedCharacterClass] = [:]
    private let index: RecordIndex?

    /// The empty store, which is what a synthetic scene, a benchmark and a unit
    /// test drive the derivation with: every actor then spreads no class points,
    /// exactly as one naming no class does.
    init() {
        index = nil
    }

    init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "CLAS" else { continue }
            guard
                case let .decoded(decoded, sourcePlugin) = index.decodeIndexed(
                    id,
                    using: Self.decode
                )
            else { continue }
            let resolved = ResolvedCharacterClass(
                id: id,
                characterClass: decoded,
                sourcePlugin: sourcePlugin
            )
            classes[id] = resolved
            if let editorID = decoded.editorID {
                classesByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["CLAS"]))
    }

    /// One plugin's classes, which is what a caller holding a single file has —
    /// the derivation's own tests and `openskycli` among them.
    init(file: ESMFile, pluginName: String) {
        self.init(plugins: [(name: pluginName, file: file)])
    }

    var isEmpty: Bool {
        classes.isEmpty
    }

    func characterClass(_ id: ResolvedFormID) -> ResolvedCharacterClass? {
        classes[id]
    }

    func characterClass(editorID: String) -> ResolvedCharacterClass? {
        classesByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard
            let index,
            case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName)
        else { return nil }
        return resolvedID
    }

    /// The class a record in `pluginName` names, resolved through the load
    /// order so a later plugin's override of the same identity wins.
    func resolve(_ id: FormID?, fromPlugin pluginName: String) -> ResolvedCharacterClass? {
        guard let id, let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return characterClass(resolvedID)
    }

    /// A class link as text: its name when the load order carries it, and an
    /// explicit unresolved marker when it does not.
    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    static func == (lhs: CharacterClassStore, rhs: CharacterClassStore) -> Bool {
        lhs.classes == rhs.classes
    }

    private static func decode(_ indexed: IndexedRecord) throws -> CharacterClass {
        try CharacterClass(record: indexed.record, localized: indexed.localized)
    }
}

nonisolated enum CharacterClassStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> CharacterClassStore {
        CharacterClassStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
