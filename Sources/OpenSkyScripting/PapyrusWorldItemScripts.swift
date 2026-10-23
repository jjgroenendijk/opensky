// Scripts on an inventory item's base record. An item in a container has no reference,
// so its scripts run on the base form's key: `OnEquipped`, `OnUnequipped`, and `OnRead`
// (<https://ck.uesp.net/wiki/OnEquipped_-_ObjectReference>). See docs/engine/papyrus-world.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Queues `name` on each script of the item `base`, creating the instances on first
    /// use. A script still loading queues the event once it loads. Returns the count queued now.
    @discardableResult
    public func queueItemEvent(
        _ name: String,
        base: ReferenceKey,
        scripts: [AttachedScript],
        arguments: [PapyrusValue],
        formIDResolver: FormIDResolver
    ) -> Int {
        let live = scripts.filter { !$0.isRemoved }
        guard !live.isEmpty else { return 0 }
        if scriptsLoading(live.map(\.name)) {
            deferUntilScriptsLoad { [weak self] in
                self?.queueItemEvent(
                    name, base: base, scripts: live, arguments: arguments,
                    formIDResolver: formIDResolver
                )
            }
            return 0
        }
        var queued = 0
        for script in live {
            let key = PapyrusInstanceKey(reference: base, scriptName: script.name)
            guard instancesByKey[key] != nil || makeItemInstance(key, script, formIDResolver)
            else { continue }
            guard handlesEvent(name, key: key) else { continue }
            enqueue(PapyrusScriptEvent(target: key, functionName: name, arguments: arguments))
            queued += 1
        }
        return queued
    }

    /// An item instance never retires: the same base form can be equipped again later.
    private func makeItemInstance(
        _ key: PapyrusInstanceKey, _ script: AttachedScript, _ resolver: FormIDResolver
    ) -> Bool {
        guard resolveScript(named: script.name) else {
            skips.note(.missingScript)
            return false
        }
        let item = PapyrusAttachItem(key: key, script: script, isPersistent: true)
        guard instantiate(item) else { return false }
        persistentKeys.insert(key)
        bind(plan: [item], created: [key], formIDResolver: resolver)
        enqueueOnInitIfNeeded(key)
        return true
    }
}
