// Load-order-wide AVIF lookup above RecordIndex, in the MagicEffectStore
// shape: winning definition per identity, editor-ID lookup, and the join that
// answers "which record describes actor value 6".
//
// The actor-value index is not stored in the record — AVIF carries a name, not
// a number — so the join runs through `ActorValueIdentity`, which is the one
// table that numbers the vanilla actor values (docs/engine/actor-values.md).
// Nothing here introduces a second skill enum.

import Foundation

nonisolated struct ResolvedActorValueInformation: Equatable {
    let id: ResolvedFormID
    let information: ActorValueInformation
    let sourcePlugin: String

    /// The vanilla actor value this record describes, or nil for a modded
    /// record naming something the vanilla table does not carry.
    var actorValueIndex: Int32? {
        information.vanillaActorValueIndex
    }

    var displayName: String {
        switch information.name {
        case let .inline(value): value
        case .tableID: information.editorID ?? id.description
        case nil: information.editorID ?? id.description
        }
    }
}

nonisolated struct ActorValueInformationStore {
    private let index: RecordIndex
    private(set) var information: [ResolvedFormID: ResolvedActorValueInformation] = [:]
    private var informationByEditorID: [String: ResolvedActorValueInformation] = [:]
    private var informationByActorValueIndex: [Int32: ResolvedActorValueInformation] = [:]

    init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "AVIF" else { continue }
            guard
                case let .decoded(decoded, sourcePlugin) = index.decodeIndexed(
                    id,
                    using: Self.decode
                )
            else { continue }
            add(ResolvedActorValueInformation(
                id: id,
                information: decoded,
                sourcePlugin: sourcePlugin
            ))
        }
    }

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["AVIF"]))
    }

    /// Every record that carries both advancement parameters and a perk tree.
    ///
    /// Wider than `skills`: on a load order with Dawnguard this also holds the
    /// vampire and werewolf trees, which hang off actor values outside the
    /// skill range and outside the vanilla name table entirely. Ordered by
    /// actor-value index, with the records the join could not number sorted
    /// last by editor id so the order stays deterministic with mods installed.
    var perkTreeRecords: [ResolvedActorValueInformation] {
        information.values
            .filter(\.information.hasPerkTree)
            .sorted { left, right in
                switch (left.actorValueIndex, right.actorValueIndex) {
                case let (leftIndex?, rightIndex?): leftIndex < rightIndex
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil):
                    (left.information.editorID ?? "") < (right.information.editorID ?? "")
                }
            }
    }

    /// The eighteen skills: the perk-tree records that join to an index inside
    /// the skill range of the vanilla actor-value table.
    var skills: [ResolvedActorValueInformation] {
        perkTreeRecords.filter { record in
            guard let index = record.actorValueIndex else { return false }
            return ActorValueIdentity.isSkill(index: index)
        }
    }

    func information(_ id: ResolvedFormID) -> ResolvedActorValueInformation? {
        information[id] ?? information.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    func information(editorID: String) -> ResolvedActorValueInformation? {
        informationByEditorID[editorID.lowercased()]
    }

    /// The record describing a vanilla actor value, by the index every CTDA
    /// parameter and every stored value uses.
    func information(actorValueIndex: Int32) -> ResolvedActorValueInformation? {
        informationByActorValueIndex[actorValueIndex]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedActorValueInformation? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return information(resolvedID)
    }

    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    private mutating func add(_ resolved: ResolvedActorValueInformation) {
        information[resolved.id] = resolved
        if let editorID = resolved.information.editorID {
            informationByEditorID[editorID.lowercased()] = resolved
        }
        if let actorValueIndex = resolved.actorValueIndex {
            informationByActorValueIndex[actorValueIndex] = resolved
        }
    }

    private static func decode(_ indexed: IndexedRecord) throws -> ActorValueInformation {
        try ActorValueInformation(record: indexed.record, localized: indexed.localized)
    }
}

nonisolated enum ActorValueInformationStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> ActorValueInformationStore {
        ActorValueInformationStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
