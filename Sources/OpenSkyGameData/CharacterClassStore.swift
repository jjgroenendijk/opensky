// Load-order-wide CLAS lookup above `RecordIndex`, so a patch plugin's class
// override wins. What a class contributes is in docs/engine/actor-values.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// One CLAS record under its load-order identity.
nonisolated public struct ResolvedCharacterClass: Equatable, Sendable {
    public let id: ResolvedFormID
    public let characterClass: CharacterClass
    public let sourcePlugin: String

    public var editorID: String? {
        characterClass.editorID
    }

    public var displayName: String {
        switch characterClass.name {
        case let .inline(value): value
        case .tableID, .pluginTableID: characterClass.editorID ?? id.description
        case nil: characterClass.editorID ?? id.description
        }
    }
}

nonisolated public struct CharacterClassStore: Equatable, Sendable {
    private let table: ResolvedRecordTable<ResolvedCharacterClass>
    private let index: RecordIndex?

    public var classes: [ResolvedFormID: ResolvedCharacterClass] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    /// The empty store, which is what a synthetic scene, a benchmark and a unit
    /// test drive the derivation with: every actor then spreads no class points.
    public init() {
        index = nil
        table = ResolvedRecordTable()
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["CLAS"],
            decode: Self.decode,
            editorID: \.editorID,
            resolve: { ResolvedCharacterClass(id: $0, characterClass: $1, sourcePlugin: $2) }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["CLAS"]))
    }

    /// One plugin's classes, which is what a caller holding a single file has —
    /// the derivation's own tests and `openskycli` among them.
    public init(file: ESMFile, pluginName: String) {
        self.init(plugins: [(name: pluginName, file: file)])
    }

    public var isEmpty: Bool {
        classes.isEmpty
    }

    public func characterClass(_ id: ResolvedFormID) -> ResolvedCharacterClass? {
        classes[id]
    }

    public func characterClass(editorID: String) -> ResolvedCharacterClass? {
        table.value(editorID: editorID)
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index?.resolvedID(id, fromPlugin: pluginName)
    }

    /// The class a record in `pluginName` names, resolved through the load
    /// order so a later plugin's override of the same identity wins.
    public func resolve(_ id: FormID?, fromPlugin pluginName: String) -> ResolvedCharacterClass? {
        guard let id, let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return characterClass(resolvedID)
    }

    /// A class link as text: its name when the load order carries it, and an
    /// explicit unresolved marker when it does not.
    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    public static func == (lhs: CharacterClassStore, rhs: CharacterClassStore) -> Bool {
        lhs.classes == rhs.classes
    }

    private static func decode(_ indexed: IndexedRecord) throws -> CharacterClass {
        try CharacterClass(record: indexed.record, localized: indexed.localized)
    }
}

nonisolated public enum CharacterClassStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> CharacterClassStore {
        CharacterClassStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
