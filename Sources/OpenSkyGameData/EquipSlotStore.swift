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
    /// Every winning EQUP identity in the load order.
    public private(set) var slots: [ResolvedFormID: ResolvedEquipSlot] = [:]
    private var slotsByEditorID: [String: ResolvedEquipSlot] = [:]

    public init(index: RecordIndex) {
        self.index = index
        let orderedIDs = index.records.keys.sorted {
            RecordStoreOrdering.precedes($0, $1, index: index)
        }
        for id in orderedIDs {
            guard index.records[id]?.record.type == "EQUP" else { continue }
            guard
                case let .decoded(slot, sourcePlugin) = index.decode(
                    id,
                    using: EquipSlot.init(record:)
                ) else { continue }
            let resolved = ResolvedEquipSlot(id: id, slot: slot, sourcePlugin: sourcePlugin)
            slots[id] = resolved
            if let editorID = slot.editorID {
                slotsByEditorID[editorID.lowercased()] = resolved
            }
        }
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["EQUP"]))
    }

    public func slot(_ id: ResolvedFormID) -> ResolvedEquipSlot? {
        slots[id] ?? slots.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    public func slot(editorID: String) -> ResolvedEquipSlot? {
        slotsByEditorID[editorID.lowercased()]
    }

    public func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    public func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedEquipSlot? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return slot(resolvedID)
    }

    public func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }
}
