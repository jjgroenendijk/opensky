// Alias slots: one quest alias as a Papyrus object, filled or not. A VMAD alias
// property binds to the slot's handle. A call through it reaches the alias script on
// the filled reference when the declared type is that script, and the alias natives
// otherwise. See docs/engine/papyrus-quests.md.

import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

/// One alias of one quest: the QUST key and the `ALST` or `ALLS` alias ID.
nonisolated public struct PapyrusAliasSlot: Hashable, Sendable {
    let quest: ReferenceKey
    let aliasID: UInt32
}

extension PapyrusWorldRuntime.QuestScriptRuns {
    /// The session-stable handle naming `slot`.
    func aliasSlotHandle(_ slot: PapyrusAliasSlot) -> PapyrusObjectHandle {
        if let existing = world.aliasSlotHandles[slot] {
            return existing
        }
        let handle = world.activationRuns.allocateOpaqueHandle()
        world.aliasSlotHandles[slot] = handle
        world.aliasSlotsByHandle[handle] = slot
        return handle
    }

    /// The slot behind a slot handle, or behind the handle of an alias script, which is
    /// `Self` inside that script.
    func aliasSlot(for handle: PapyrusObjectHandle) -> PapyrusAliasSlot? {
        world.aliasSlotsByHandle[handle] ?? world.keysByHandle[handle]
            .flatMap { world.aliasSlotsByInstance[$0] }
    }

    func aliasReference(in slot: PapyrusAliasSlot) -> ReferenceKey? {
        world.aliasResolution.table(forKey: slot.quest).reference(forAlias: slot.aliasID)
    }

    func aliasLocation(in slot: PapyrusAliasSlot) -> ResolvedFormID? {
        world.aliasResolution.table(forKey: slot.quest).location(forAlias: slot.aliasID)
    }

    /// The lowest-script-name alias script serving `slot` whose script is `typeName` or
    /// extends it. Nil while the alias is empty.
    func aliasInstance(of slot: PapyrusAliasSlot, as typeName: String) -> PapyrusObjectHandle? {
        world.aliasSlotsByInstance.filter { $0.value == slot }.keys.sorted().lazy
            .compactMap { world.instancesByKey[$0] }
            .first { world.runtime.resolvesObject($0, as: typeName) }
    }

    /// Retires the alias scripts of `slot` that no longer sit on its filled reference,
    /// so a new fill attaches fresh ones. Returns how many went.
    @discardableResult
    func retireAliasScripts(of slot: PapyrusAliasSlot) -> Int {
        let current = aliasReference(in: slot)
        let stale = world.aliasSlotsByInstance
            .filter { $0.value == slot && $0.key.reference != current }
            .keys.sorted()
        for key in stale {
            world.lifecycle.retire(key)
            world.aliasSlotsByInstance.removeValue(forKey: key)
            world.questAliasInstanceKeys[slot.quest]?.remove(key)
            world.persistentKeys.remove(key)
            world.firedOnInit.remove(key)
        }
        return stale.count
    }
}
