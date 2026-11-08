// `OnOpen`, `OnClose`, `OnLockStateChanged`, and `OnContainerChanged` for a picked-up
// reference, from the world-state journal (<https://ck.uesp.net/wiki/OnOpen_-_ObjectReference>,
// <https://ck.uesp.net/wiki/OnContainerChanged_-_ObjectReference>). See
// docs/engine/papyrus-world.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge {
    /// Queues the events for the activation, lock, and deletion writes since the last
    /// call. The first call only sets the cursor. Returns the count.
    @discardableResult
    public func queueReferenceStateEvents() -> Int {
        let next = worldState.nextJournalSequence
        defer { referenceJournalCursor = next }
        guard let cursor = referenceJournalCursor, cursor < next, let world else { return 0 }
        let entries = worldState.journalEntries(since: cursor)
            .filter { [.activation, .lock, .deletion, .inventory].contains($0.kind) }
        var queued = 0
        for (index, entry) in entries.enumerated()
            where !world.instanceKeys(on: entry.key).isEmpty
        {
            switch entry.kind {
            case .activation:
                queued += queueOpenStateEvent(entry, in: world)
            case .lock:
                queued += queueLockStateEvent(entry, in: world)
            case .deletion where index > 0:
                queued += queuePickUpEvent(entry, after: entries[index - 1], in: world)
            default:
                break
            }
        }
        return queued
    }

    /// Starts the next read at the journal's end, so a load is not read as changes.
    public func skipReferenceStateJournal() {
        referenceJournalCursor = worldState.nextJournalSequence
    }

    private func queueOpenStateEvent(
        _ entry: WorldStateJournalEntry, in world: PapyrusWorldRuntime
    ) -> Int {
        let old = entry.oldValue?.value(as: ReferenceActivationState.self) ?? .untouched
        let new = entry.newValue?.value(as: ReferenceActivationState.self) ?? .untouched
        guard old.isOpen != new.isOpen else { return 0 }
        let name = new.isOpen ? PapyrusEngineEvents.onOpen : PapyrusEngineEvents.onClose
        let actor = new.lastActivator.map { PapyrusValue.object(world.objectHandle(for: $0)) }
        return queueReferenceEvent(name, on: entry.key, [actor ?? .none], in: world)
    }

    private func queueLockStateEvent(
        _ entry: WorldStateJournalEntry, in world: PapyrusWorldRuntime
    ) -> Int {
        let baseline = placedReference(for: entry.key)?.lock
        let isLocked = { (value: WorldStateComponentValue?) in
            ReferenceLockState.resolve(
                baseline: baseline, delta: value?.value(as: ReferenceLockState.self)
            )?.isLocked ?? false
        }
        guard isLocked(entry.oldValue) != isLocked(entry.newValue) else { return 0 }
        return queueReferenceEvent(
            PapyrusEngineEvents.onLockStateChanged,
            on: entry.key,
            [],
            in: world
        )
    }

    /// A take adds the item to the taker and then deletes the reference, so a deletion
    /// right after a write that added this reference's base names the new container.
    private func queuePickUpEvent(
        _ entry: WorldStateJournalEntry, after previous: WorldStateJournalEntry,
        in world: PapyrusWorldRuntime
    ) -> Int {
        guard
            entry.newValue?.value(as: ReferenceDeletionState.self)?.isDeleted == true,
            previous.kind == .inventory, previous.key != entry.key,
            let base = baseObject(of: entry.key),
            itemCount(base, in: previous.newValue) > itemCount(base, in: previous.oldValue)
        else { return 0 }
        let taker = PapyrusValue.object(world.objectHandle(for: previous.key))
        return queueReferenceEvent(
            PapyrusEngineEvents.onContainerChanged, on: entry.key, [taker, .none], in: world
        )
    }

    private func itemCount(_ item: FormID, in value: WorldStateComponentValue?) -> Int64 {
        let stacks = value.flatMap(ReferenceInventoryState.init(erased:))?.stacks ?? []
        return stacks.filter { $0.item == item }.reduce(0) { $0 + Int64($1.count) }
    }

    func queueReferenceEvent(
        _ name: String, on key: ReferenceKey, _ arguments: [PapyrusValue],
        in world: PapyrusWorldRuntime
    ) -> Int {
        var queued = 0
        for instance in world.instanceKeys(on: key) where world.handlesEvent(name, key: instance) {
            world.enqueue(PapyrusScriptEvent(
                target: instance,
                functionName: name,
                arguments: arguments
            ))
            queued += 1
        }
        return queued
    }
}
