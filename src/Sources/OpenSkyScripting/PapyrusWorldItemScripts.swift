// Scripts on an inventory item's base record. An item in a container has no reference,
// so its scripts run on the base form's key: `OnEquipped`, `OnUnequipped`, and `OnRead`
// (<https://ck.uesp.net/wiki/OnEquipped_-_ObjectReference>). See docs/engine/papyrus-world.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.ScriptEvents {
    /// Queues `name` on each script of the item `base`, creating the instances on first
    /// use. A script still loading queues the event once it loads. Returns the count queued now.
    @discardableResult
    public func queueItemEvent(
        _ event: (name: String, arguments: [PapyrusValue]),
        base: ReferenceKey,
        scripts: [AttachedScript],
        formIDResolver: FormIDResolver
    ) -> Int {
        let (name, arguments) = event
        let live = scripts.filter { !$0.isRemoved }
        guard !live.isEmpty else { return 0 }
        if world.lifecycle.scriptsLoading(live.map(\.name)) {
            world.lifecycle.deferUntilScriptsLoad { [weak world] in
                world?.scriptEvents.queueItemEvent(
                    event, base: base, scripts: live,
                    formIDResolver: formIDResolver
                )
            }
            return 0
        }
        var queued = 0
        for script in live {
            let key = PapyrusInstanceKey(reference: base, scriptName: script.name)
            guard
                world.instancesByKey[key] != nil || makeItemInstance(key, script, formIDResolver),
                handlesEvent(
                    name,
                    key: key
                ) else { continue }
            world.enqueue(PapyrusScriptEvent(target: key, functionName: name, arguments: arguments))
            queued += 1
        }
        return queued
    }

    /// An item instance never retires: the same base form can be equipped again later.
    private func makeItemInstance(
        _ key: PapyrusInstanceKey, _ script: AttachedScript, _ resolver: FormIDResolver
    ) -> Bool {
        guard world.resolveScript(named: script.name) else {
            world.skips.note(.missingScript)
            return false
        }
        let item = PapyrusAttachItem(key: key, script: script, isPersistent: true)
        guard world.lifecycle.instantiate(item) else { return false }
        world.persistentKeys.insert(key)
        world.lifecycle.bind(plan: [item], created: [key], formIDResolver: resolver)
        world.enqueueOnInitIfNeeded(key)
        return true
    }
}
