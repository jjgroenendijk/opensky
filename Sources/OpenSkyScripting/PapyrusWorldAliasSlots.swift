// Alias slots: one quest alias as a Papyrus object, filled or not. A VMAD alias
// property binds to the slot's handle. A call through it reaches the alias script on
// the filled reference when the declared type is that script, and the alias natives
// otherwise. See docs/engine/papyrus-quests.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface

/// One alias of one quest: the QUST key and the `ALST` or `ALLS` alias ID.
nonisolated public struct PapyrusAliasSlot: Hashable, Sendable {
    public let quest: ReferenceKey
    public let aliasID: UInt32

    public init(quest: ReferenceKey, aliasID: UInt32) {
        self.quest = quest
        self.aliasID = aliasID
    }
}

extension PapyrusWorldRuntime {
    /// The session-stable handle naming `slot`.
    public func aliasSlotHandle(_ slot: PapyrusAliasSlot) -> PapyrusObjectHandle {
        if let existing = aliasSlotHandles[slot] {
            return existing
        }
        let handle = allocateOpaqueHandle()
        aliasSlotHandles[slot] = handle
        aliasSlotsByHandle[handle] = slot
        return handle
    }

    /// The slot behind a slot handle, or behind the handle of an alias script, which is
    /// `Self` inside that script.
    public func aliasSlot(for handle: PapyrusObjectHandle) -> PapyrusAliasSlot? {
        aliasSlotsByHandle[handle] ?? keysByHandle[handle].flatMap { aliasSlotsByInstance[$0] }
    }

    func aliasReference(in slot: PapyrusAliasSlot) -> ReferenceKey? {
        aliasResolution.table(forKey: slot.quest).reference(forAlias: slot.aliasID)
    }

    func aliasLocation(in slot: PapyrusAliasSlot) -> ResolvedFormID? {
        aliasResolution.table(forKey: slot.quest).location(forAlias: slot.aliasID)
    }

    /// The lowest-script-name alias script serving `slot` whose script is `typeName` or
    /// extends it. Nil while the alias is empty.
    func aliasInstance(of slot: PapyrusAliasSlot, as typeName: String) -> PapyrusObjectHandle? {
        aliasSlotsByInstance.filter { $0.value == slot }.keys.sorted().lazy
            .compactMap { self.instancesByKey[$0] }
            .first { self.runtime.resolvesObject($0, as: typeName) }
    }

    /// Retires the alias scripts of `slot` that no longer sit on its filled reference,
    /// so a new fill attaches fresh ones. Returns how many went.
    @discardableResult
    public func retireAliasScripts(of slot: PapyrusAliasSlot) -> Int {
        let current = aliasReference(in: slot)
        let stale = aliasSlotsByInstance
            .filter { $0.value == slot && $0.key.reference != current }
            .keys.sorted()
        for key in stale {
            retire(key)
            aliasSlotsByInstance.removeValue(forKey: key)
            questAliasInstanceKeys[slot.quest]?.remove(key)
            persistentKeys.remove(key)
            firedOnInit.remove(key)
        }
        return stale.count
    }
}
