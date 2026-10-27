// Item and equip events from the world-state journal: every inventory write since the
// last frame, diffed old against new. The two writes of one transfer sit next to each
// other, so each side names the other as its container. See docs/engine/papyrus-world.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge {
    /// Queues `OnItemAdded`, `OnItemRemoved`, `OnObjectEquipped`, and `OnObjectUnequipped`
    /// for the inventory writes since the last call. The first call only sets the cursor.
    @discardableResult
    public func queueInventoryEvents() -> Int {
        let next = worldState.nextJournalSequence
        defer {
            inventoryJournalCursor = next
            scriptedEquipHolders = []
        }
        guard let cursor = inventoryJournalCursor, cursor < next, let world else { return 0 }
        let changes = worldState.journalEntries(since: cursor)
            .filter { $0.kind == .inventory }
            .compactMap(inventoryChange)
        var queued = 0
        for (index, change) in changes.enumerated() {
            queued += queueItemEquipEvents(change, in: world)
            guard !world.instanceKeys(on: change.holder).isEmpty else { continue }
            let before = index > 0 ? changes[index - 1] : nil
            let after = index + 1 < changes.count ? changes[index + 1] : nil
            queued += queueItemEvents(change, before: before, after: after, in: world)
            queued += queueEquipEvents(change, in: world)
        }
        return queued
    }

    /// Queues `name` on the scripts of the item `base` itself. Returns the count.
    @discardableResult
    public func queueItemScriptEvent(
        _ name: String, base: ReferenceKey, arguments: [PapyrusValue]
    ) -> Int {
        guard
            let world, let formIDResolver,
            let scripts = sessionNatives.itemScripts?(base), !scripts.isEmpty
        else { return 0 }
        return world.queueItemEvent(
            name, base: base, scripts: scripts, arguments: arguments,
            formIDResolver: formIDResolver
        )
    }

    /// Marks `holder`'s next equip changes as a script's, so the items' own scripts hear
    /// nothing of them. An item the script's equip pushes out of its slot counts too.
    public func noteScriptedEquip(on holder: ReferenceKey) {
        scriptedEquipHolders.insert(holder)
    }

    /// `OnEquipped(Actor akActor)` and `OnUnequipped(Actor akActor)` on the item's own
    /// scripts, whoever wears it. The wiki says an equip by a script or the console sends
    /// neither (<https://ck.uesp.net/wiki/OnEquipped_-_ObjectReference>).
    private func queueItemEquipEvents(
        _ change: InventoryChange, in world: PapyrusWorldRuntime
    ) -> Int {
        guard !scriptedEquipHolders.contains(change.holder) else { return 0 }
        let old = Set(change.old.equipped)
        let new = Set(change.new.equipped)
        let actor = PapyrusValue.object(world.objectHandle(for: change.holder))
        var queued = 0
        for (items, name) in [
            (new.subtracting(old), PapyrusEngineEvents.onEquipped),
            (old.subtracting(new), PapyrusEngineEvents.onUnequipped)
        ] {
            for item in items.sorted(by: { $0.rawValue < $1.rawValue }) {
                guard let base = itemKey(item) else { continue }
                queued += queueItemScriptEvent(name, base: base, arguments: [actor])
            }
        }
        return queued
    }

    /// Starts the next read at the journal's end, so a load is not read as item moves.
    public func skipInventoryJournal() {
        inventoryJournalCursor = worldState.nextJournalSequence
        scriptedEquipHolders = []
    }

    private func inventoryChange(_ entry: WorldStateJournalEntry) -> InventoryChange? {
        let baseline = { [inventory] in inventory?.baselineInventory(of: entry.key) }
        guard
            let old = entry.oldValue.flatMap(ReferenceInventoryState.init(erased:)) ?? baseline(),
            let new = entry.newValue.flatMap(ReferenceInventoryState.init(erased:)) ?? baseline()
        else { return nil }
        return InventoryChange(holder: entry.key, old: old, new: new)
    }

    private func queueItemEvents(
        _ change: InventoryChange, before: InventoryChange?, after: InventoryChange?,
        in world: PapyrusWorldRuntime
    ) -> Int {
        var queued = 0
        for (item, delta) in change.countDeltas {
            let added = delta > 0
            // The other side of a transfer moved the same count the other way.
            let other = [before, after].compactMap(\.self).first {
                $0.holder != change.holder && $0.countDeltas[item] == -delta
            }
            let name = added ? PapyrusEngineEvents.onItemAdded : PapyrusEngineEvents.onItemRemoved
            queued += queueInventoryEvent(name, on: change.holder, item: item, in: world, [
                formValue(item, in: world), .integer(abs(delta)), .none,
                other.map { .object(world.objectHandle(for: $0.holder)) } ?? .none
            ])
        }
        return queued
    }

    private func queueEquipEvents(_ change: InventoryChange, in world: PapyrusWorldRuntime) -> Int {
        let old = Set(change.old.equipped)
        let new = Set(change.new.equipped)
        var queued = 0
        for (items, name) in [
            (new.subtracting(old), PapyrusEngineEvents.onObjectEquipped),
            (old.subtracting(new), PapyrusEngineEvents.onObjectUnequipped)
        ] {
            for item in items.sorted(by: { $0.rawValue < $1.rawValue }) {
                queued += queueInventoryEvent(
                    name, on: change.holder, item: nil, in: world, [
                        formValue(item, in: world),
                        .none
                    ]
                )
            }
        }
        return queued
    }

    /// Queues on each instance on `holder` that handles `name`. An item event also needs
    /// the item to pass the instance's filters.
    private func queueInventoryEvent(
        _ name: String, on holder: ReferenceKey, item: FormID?, in world: PapyrusWorldRuntime,
        _ arguments: [PapyrusValue]
    ) -> Int {
        let itemKey = item.flatMap(itemKey)
        var queued = 0
        for key in world.instanceKeys(on: holder) where world.definesFunction(name, key: key) {
            if item != nil, !passesInventoryFilters(itemKey, instance: key) {
                continue
            }
            world.enqueue(PapyrusScriptEvent(target: key, functionName: name, arguments: arguments))
            queued += 1
        }
        return queued
    }

    private func itemKey(_ item: FormID) -> ReferenceKey? {
        formIDResolver.flatMap { ReferenceKey.resolve(item, using: $0) }
    }

    private func formValue(_ item: FormID, in world: PapyrusWorldRuntime) -> PapyrusValue {
        itemKey(item).map { .object(world.objectHandle(for: $0)) } ?? .none
    }
}

/// One holder's inventory before and after one write.
private struct InventoryChange {
    let holder: ReferenceKey
    let old: ReferenceInventoryState
    let new: ReferenceInventoryState

    /// Count change per item, honest and stolen copies together. Zero changes drop out.
    var countDeltas: [FormID: Int32] {
        var deltas: [FormID: Int32] = [:]
        for stack in new.stacks {
            deltas[stack.item, default: 0] &+= stack.count
        }
        for stack in old.stacks {
            deltas[stack.item, default: 0] &-= stack.count
        }
        return deltas.filter { $0.value != 0 }
    }
}
