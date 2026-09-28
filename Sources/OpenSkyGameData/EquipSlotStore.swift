// Load-order-wide EQUP lookup above RecordIndex, in the shape `KeywordStore`
// and `SpellStore` already use.
//
// `EquipSlotTable` answers the same question for one plugin and is what
// `EquipmentCatalog` uses; this store exists for the consumers that hold a
// whole load order — the Asset Browser inspector, the CLI record dump, and the
// real-data sweep that checks every WEAP and SPEL ETYP resolves. Both share
// `EquipSlotHands`, so there is one implementation of the parent walk.
//
// Parent links resolve relative to the plugin the EQUP came from, which is
// what lets a mod-added slot name a vanilla hand as its parent.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedEquipSlot: Equatable, Sendable {
    public let id: ResolvedFormID
    public let slot: EquipSlot
    public let sourcePlugin: String

    public var editorID: String? {
        slot.editorID
    }

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

nonisolated public enum EquipSlotStoreLoader: Sendable {
    public static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> EquipSlotStore {
        EquipSlotStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
