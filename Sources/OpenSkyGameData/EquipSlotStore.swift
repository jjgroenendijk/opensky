// Load-order-wide EQUP lookup above RecordIndex, for consumers that hold a whole
// load order. `EquipSlotTable` answers for one plugin. Both share
// `EquipSlotHands` for the parent walk. Parent links resolve relative to the
// EQUP's plugin, so a mod slot can name a vanilla hand.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedEquipSlot: Equatable, Sendable {
    public let id: ResolvedFormID
    public let slot: EquipSlot
    public let sourcePlugin: String

    public var displayName: String {
        slot.editorID ?? id.description
    }
}

nonisolated public struct EquipSlotStore: Sendable {
    private let index: RecordIndex
    private let table: ResolvedRecordTable<ResolvedEquipSlot>

    /// Every winning EQUP identity in the load order.
    public var slots: [ResolvedFormID: ResolvedEquipSlot] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        self.index = index
        table = ResolvedRecordTable(
            index: index,
            types: ["EQUP"],
            decode: { try EquipSlot(record: $0.record) },
            editorID: \.editorID,
            resolve: { ResolvedEquipSlot(id: $0, slot: $1, sourcePlugin: $2) }
        )
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["EQUP"]))
    }

    public func slot(_ id: ResolvedFormID) -> ResolvedEquipSlot? {
        table.value(id)
    }

    public func slot(editorID: String) -> ResolvedEquipSlot? {
        table.value(editorID: editorID)
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        index.resolvedID(id, fromPlugin: pluginName)
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedEquipSlot? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return slot(resolvedID)
    }

    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }
}
