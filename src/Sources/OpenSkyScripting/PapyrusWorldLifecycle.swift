// Cell attach and detach for `PapyrusWorldRuntime`. It takes plain data, not a
// `CellStreamer`, so tests use synthetic fixtures. `instantiate`, `bind` and
// `retire` are internal because quest scripts (PapyrusWorldQuests.swift) reuse them.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyScriptingInterface
public import OpenSkyWorldState

/// One script slated for instantiation during an attach, in deterministic
/// `sortedEntries()` × VMAD-script order.
nonisolated public struct PapyrusAttachItem: Sendable {
    public let key: PapyrusInstanceKey
    public let script: AttachedScript
    public let isPersistent: Bool
}

extension PapyrusWorldRuntime.Lifecycle {
    /// Creates instances for every reference with VMAD script data and enqueues
    /// `OnInit` (if never fired), `OnCellAttach`, `OnLoad`, then `OnCellLoad`. On a rebuild
    /// (`firstIntegration == false`) only new references get `OnInit`.
    public func attach(
        cell: CellSceneLocation,
        references: RuntimeReferenceIndex,
        formIDResolver: FormIDResolver,
        firstIntegration: Bool
    ) {
        let scripts = references.sortedEntries().flatMap(attachedScripts(of:))
            .filter { !$0.isRemoved }
        let names = scripts.map(\.name) + targetScripts(of: scripts, resolver: formIDResolver)
        if world.deferredScriptWork.contains(where: { $0.cell == cell }) || scriptsLoading(names) {
            deferUntilScriptsLoad(cell: cell) { [weak world] in
                world?.attach(
                    cell: cell, references: references, formIDResolver: formIDResolver,
                    firstIntegration: firstIntegration
                )
            }
            return
        }
        world.retainFormIDResolver(formIDResolver)
        let plan = collectAttachPlan(references: references)
        var attached = world.attachedByCell[cell] ?? []
        var created: Set<PapyrusInstanceKey> = []
        for item in plan {
            attached.insert(item.key)
            world.retiringKeys.remove(item.key)
            if item.isPersistent {
                world.persistentKeys.insert(item.key)
            }
            if world.instancesByKey[item.key] == nil, instantiate(item) {
                created.insert(item.key)
            }
        }
        world.attachedByCell[cell] = attached
        bind(plan: plan, created: created, formIDResolver: formIDResolver)
        enqueueAttachEvents(
            plan: plan, created: created, firstIntegration: firstIntegration
        )
        if firstIntegration {
            enqueueCellLoad(references: references)
            world.cellLoadedReferences[cell] = Set(references.sortedEntries().map(\.key))
        }
    }

    /// `OnCellLoad` goes to every script on the cell's references, alias scripts
    /// included, once the cell is in the scene (<https://ck.uesp.net/wiki/OnCellLoad>).
    private func enqueueCellLoad(references: RuntimeReferenceIndex) {
        for entry in references.sortedEntries() {
            for key in world.instanceKeys(on: entry.key) {
                world.enqueue(PapyrusScriptEvent(
                    target: key, functionName: PapyrusEngineEvents.onCellLoad, arguments: []
                ))
            }
        }
    }

    /// Queues `OnUnload` then `OnCellDetach`, the reverse of the attach order, and retires
    /// the cell's instances. A persistent instance survives with its variables. Any other
    /// instance that handles one of the two events retires once they have run.
    public func detach(cell: CellSceneLocation) {
        world.deferredScriptWork.removeAll { $0.cell == cell }
        if let unloaded = world.cellLoadedReferences.removeValue(forKey: cell) {
            world.scriptEvents.dropAnimationEvents(of: unloaded)
        }
        guard let keys = world.attachedByCell.removeValue(forKey: cell) else {
            return
        }
        for key in keys.sorted() {
            let handles = enqueueDetachEvents(key)
            guard !world.persistentKeys.contains(key) else { continue }
            if handles {
                world.retiringKeys.insert(key)
            } else {
                retire(key)
            }
        }
    }

    /// True when the instance defines either event.
    private func enqueueDetachEvents(_ key: PapyrusInstanceKey) -> Bool {
        var handles = false
        for name in [PapyrusEngineEvents.onUnload, PapyrusEngineEvents.onCellDetach]
            where world.scriptEvents.definesFunction(name, key: key)
        {
            world.enqueue(PapyrusScriptEvent(target: key, functionName: name, arguments: []))
            handles = true
        }
        return handles
    }

    /// Retires each detached instance whose queued events have all run.
    func retireDrainedInstances() {
        guard !world.retiringKeys.isEmpty else { return }
        let waiting = Set(world.eventQueue.map(\.target)).union(world.busyInstances)
        for key in world.retiringKeys.sorted() where !waiting.contains(key) {
            world.retiringKeys.remove(key)
            retire(key)
        }
    }

    private func collectAttachPlan(
        references: RuntimeReferenceIndex
    ) -> [PapyrusAttachItem] {
        var plan: [PapyrusAttachItem] = []
        var seen: Set<PapyrusInstanceKey> = []
        for entry in references.sortedEntries() {
            for script in attachedScripts(of: entry) {
                guard !script.isRemoved else {
                    world.skips.note(.removedScript)
                    continue
                }
                guard world.resolveScript(named: script.name) else {
                    world.skips.note(.missingScript)
                    continue
                }
                let key = PapyrusInstanceKey(
                    reference: entry.key, scriptName: script.name
                )
                guard seen.insert(key).inserted else {
                    continue
                }
                plan.append(PapyrusAttachItem(
                    key: key, script: script, isPersistent: entry.isPersistent
                ))
            }
        }
        return plan
    }

    private func attachedScripts(
        of entry: RuntimeReferenceEntry
    ) -> [AttachedScript] {
        entry.scripts
    }

    /// A persistent reference keeps its scripts while its cell is unloaded, so they
    /// attach on first use and stay. A later cell attach keeps them and fires no
    /// second `OnInit`. Returns the instances created.
    @discardableResult
    func attachUnloaded(
        _ entry: RuntimeReferenceEntry,
        formIDResolver: FormIDResolver
    ) -> Int {
        let names = attachedScripts(of: entry).filter { !$0.isRemoved }.map(\.name)
        guard !names.isEmpty, !scriptsLoading(names) else { return 0 }
        let plan = collectAttachPlan(references: RuntimeReferenceIndex(entries: [entry]))
        var created: Set<PapyrusInstanceKey> = []
        for item in plan {
            world.persistentKeys.insert(item.key)
            if world.instancesByKey[item.key] == nil, instantiate(item) {
                created.insert(item.key)
            }
        }
        bind(plan: plan, created: created, formIDResolver: formIDResolver)
        for item in plan where created.contains(item.key) {
            world.enqueueOnInitIfNeeded(item.key)
        }
        return created.count
    }

    public func instantiate(_ item: PapyrusAttachItem) -> Bool {
        do {
            let handle = try world.runtime.makeInstance(scriptName: item.script.name)
            world.storeInstance(handle, for: item.key)
            return true
        } catch {
            world.skips.note(.instanceCreationFailed)
            return false
        }
    }

    /// Second attach pass: bind VMAD properties once every instance in the
    /// cell exists, so intra-cell object properties resolve to live handles.
    public func bind(
        plan: [PapyrusAttachItem],
        created: Set<PapyrusInstanceKey>,
        formIDResolver: FormIDResolver
    ) {
        guard !created.isEmpty else {
            return
        }
        for item in plan where created.contains(item.key) {
            bind(item, formIDResolver: formIDResolver)
        }
    }

    private func bind(
        _ item: PapyrusAttachItem,
        formIDResolver: FormIDResolver
    ) {
        guard
            let handle = world.instancesByKey[item.key],
            let instance = world.runtime.instance(for: handle),
            let chain = attempt({ try world.runtime.scriptChain(from: item.script.name) })
        else {
            world.skips.note(.bindingFailed)
            return
        }
        do {
            let binding = try item.script.binding(
                in: world.runtime,
                formIDResolver: formIDResolver,
                aliases: world.aliasResolution,
                aliasHandle: {
                    world.activationRuns.aliasInstanceHandle(for: $0) ?? world.objectHandle(for: $0)
                },
                aliasSlot: { quest, aliasID in
                    let slot = PapyrusAliasSlot(quest: quest, aliasID: aliasID)
                    return world.questRuns.aliasSlotHandle(slot)
                },
                objectHandle: { world.objectHandle(for: $0) }
            )
            world.bindingSkips.merge(binding.skipped)
            for (name, value) in binding.initialValues.sorted(by: { $0.key < $1.key })
                where !instance.applyInitialValue(
                    value, named: name, scriptChain: chain
                )
            {
                world.skips.note(.bindingFailed)
            }
            for setting in binding.propertySettings {
                let outcome = world.runtime.setProperty(
                    setting.propertyName, on: handle, to: setting.value
                )
                if world.scriptEvents.settle(outcome, target: item.key) {
                    world.skips.note(.bindingFailed)
                }
            }
        } catch {
            world.skips.note(.bindingFailed)
        }
    }

    private func enqueueAttachEvents(
        plan: [PapyrusAttachItem],
        created: Set<PapyrusInstanceKey>,
        firstIntegration: Bool
    ) {
        if firstIntegration {
            for item in plan {
                world.enqueueOnInitIfNeeded(item.key)
                world.enqueue(PapyrusScriptEvent(
                    target: item.key,
                    functionName: PapyrusEngineEvents.onCellAttach,
                    arguments: []
                ))
                world.enqueue(PapyrusScriptEvent(
                    target: item.key,
                    functionName: PapyrusEngineEvents.onLoad,
                    arguments: []
                ))
            }
        } else {
            for item in plan where created.contains(item.key) {
                world.enqueueOnInitIfNeeded(item.key)
            }
        }
    }

    /// Another script may still hold the handle, for example a property naming a quest
    /// that stopped, so the handle stays a name for its reference.
    public func retire(_ key: PapyrusInstanceKey) {
        guard let handle = world.removeInstance(for: key) else {
            return
        }
        world.opaqueKeysByHandle[handle] = key.reference
        world.runtime.instances.removeValue(forKey: handle)
        if let cursor = world.drainCursor {
            world.drainCursor = cursor - world.eventQueue.prefix(cursor).count { $0.target == key }
        }
        world.eventQueue.removeAll { $0.target == key }
        world.updateTimers.removeAll(for: key)
        // A stopped quest drops its registrations (CK wiki "RegisterForSleep - Form").
        world.sleepListeners.remove(key)
        world.trackedStatListeners.remove(key)
        world.pendingOnInit.remove(key)
        world.retiringKeys.remove(key)
        world.handledEvents[key] = nil
        // A later run of the effect makes a new instance, which gets its own `OnInit`.
        if world.effectScripts.forget(instance: key) {
            world.firedOnInit.remove(key)
        }
        world.scheduler.cancel(world.suspensionTracker.forget(instance: key))
    }
}
