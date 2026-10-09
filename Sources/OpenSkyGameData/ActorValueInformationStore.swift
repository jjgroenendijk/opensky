// Load-order-wide AVIF lookup above RecordIndex. AVIF carries a name, not an
// actor-value number, so the index join runs through `ActorValueIdentity`
// (docs/engine/actor-values.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedActorValueInformation: Equatable, Sendable {
    public let id: ResolvedFormID
    public let information: ActorValueInformation
    public let sourcePlugin: String

    /// The vanilla actor value this record describes, or nil for a modded
    /// record naming something the vanilla table does not carry.
    public var actorValueIndex: Int32? {
        information.vanillaActorValueIndex
    }

    public var displayName: String {
        switch information.name {
        case let .inline(value): value
        case .tableID, .pluginTableID: information.editorID ?? id.description
        case nil: information.editorID ?? id.description
        }
    }
}

nonisolated public struct ActorValueInformationStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedActorValueInformation>
    private var informationByActorValueIndex: [Int32: ResolvedActorValueInformation] = [:]

    public var information: [ResolvedFormID: ResolvedActorValueInformation] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["AVIF"],
            decode: Self.decode,
            editorID: \.editorID,
            resolve: {
                ResolvedActorValueInformation(id: $0, information: $1, sourcePlugin: $2)
            }
        )
        for resolved in table.orderedValues {
            if let actorValueIndex = resolved.actorValueIndex {
                informationByActorValueIndex[actorValueIndex] = resolved
            }
        }
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["AVIF"]))
    }

    /// Every record with both advancement parameters and a perk tree. Wider
    /// than `skills`: Dawnguard adds the vampire and werewolf trees. Sorted by
    /// actor-value index, then by editor ID for records without one.
    public var perkTreeRecords: [ResolvedActorValueInformation] {
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
    public var skills: [ResolvedActorValueInformation] {
        perkTreeRecords.filter { record in
            guard let index = record.actorValueIndex else { return false }
            return ActorValueIdentity.isSkill(index: index)
        }
    }

    public func information(_ id: ResolvedFormID) -> ResolvedActorValueInformation? {
        table.value(id)
    }

    public func information(editorID: String) -> ResolvedActorValueInformation? {
        table.value(editorID: editorID)
    }

    /// The record describing a vanilla actor value, by the index every CTDA
    /// parameter and every stored value uses.
    public func information(actorValueIndex: Int32) -> ResolvedActorValueInformation? {
        informationByActorValueIndex[actorValueIndex]
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(
        _ id: FormID,
        fromPlugin pluginName: String
    ) -> ResolvedActorValueInformation? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return information(resolvedID)
    }

    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    private static func decode(_ indexed: IndexedRecord) throws -> ActorValueInformation {
        try ActorValueInformation(record: indexed.record, localized: indexed.localized)
    }
}

nonisolated public enum ActorValueInformationStoreLoader: Sendable {
    public static func load(
        root: GameDataRoot,
        baseFile: ESMFile? = nil
    ) -> ActorValueInformationStore {
        ActorValueInformationStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
