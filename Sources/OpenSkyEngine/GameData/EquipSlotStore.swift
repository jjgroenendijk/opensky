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

nonisolated struct ResolvedEquipSlot: Equatable {
    let id: ResolvedFormID
    let slot: EquipSlot
    let sourcePlugin: String

    var editorID: String? {
        slot.editorID
    }

    var displayName: String {
        slot.editorID ?? id.description
    }
}

nonisolated struct EquipSlotStore {
    private let index: RecordIndex
    /// Every winning EQUP identity in the load order.
    private(set) var slots: [ResolvedFormID: ResolvedEquipSlot] = [:]
    private var slotsByEditorID: [String: ResolvedEquipSlot] = [:]

    init(index: RecordIndex) {
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

    init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["EQUP"]))
    }

    func slot(_ id: ResolvedFormID) -> ResolvedEquipSlot? {
        slots[id] ?? slots.first { key, _ in
            key.objectID == id.objectID
                && key.plugin.caseInsensitiveCompare(id.plugin) == .orderedSame
        }?.value
    }

    func slot(editorID: String) -> ResolvedEquipSlot? {
        slotsByEditorID[editorID.lowercased()]
    }

    func resolvedID(_ id: FormID, fromPlugin pluginName: String) -> ResolvedFormID? {
        guard case let .resolved(resolvedID) = index.resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return resolvedID
    }

    func resolve(_ id: FormID, fromPlugin pluginName: String) -> ResolvedEquipSlot? {
        guard let resolvedID = resolvedID(id, fromPlugin: pluginName) else { return nil }
        return slot(resolvedID)
    }

    func displayString(for id: FormID, fromPlugin pluginName: String) -> String {
        resolve(id, fromPlugin: pluginName)?.displayName ?? "[UNRESOLVED] \(id)"
    }

    /// The hands the slot named by `id` occupies, or nil when the link names
    /// no EQUP in the load order. `[]` is a resolved slot that takes no hand —
    /// Voice and Potion — and is not a miss.
    func hands(of id: FormID?, fromPlugin pluginName: String) -> HandSlots? {
        handChoice(of: id, fromPlugin: pluginName)?.hands
    }

    /// The same answer keeping the all-parents/choose-one distinction, which is
    /// what equipping a spell to a named hand needs (issue #470).
    func handChoice(
        of id: FormID?,
        fromPlugin pluginName: String
    ) -> EquipSlotHandChoice? {
        guard let id, !id.isNull, let resolved = resolve(id, fromPlugin: pluginName) else {
            return nil
        }
        return EquipSlotHands.choice(of: resolved.slot) { parent in
            resolve(parent, fromPlugin: resolved.sourcePlugin)?.slot
        }
    }
}

nonisolated enum EquipSlotStoreLoader {
    static func load(root: GameDataRoot, baseFile: ESMFile? = nil) -> EquipSlotStore {
        EquipSlotStore(plugins: ActivePluginFiles.load(root: root, baseFile: baseFile))
    }
}
