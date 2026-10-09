// Cell attach and detach for `PapyrusWorldRuntime`. It takes plain data, not a
// `CellStreamer`, so tests use synthetic fixtures. `instantiate`, `bind` and
// `retire` are internal because quest scripts (PapyrusWorldQuests.swift) reuse them.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface
import OpenSkyWorldState

/// One script slated for instantiation during an attach, in deterministic
/// `sortedEntries()` × VMAD-script order.
nonisolated public struct PapyrusAttachItem: Sendable {
    public let key: PapyrusInstanceKey
    public let script: AttachedScript
    public let isPersistent: Bool
}

extension PapyrusWorldRuntime {
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
        if deferredScriptWork.contains(where: { $0.cell == cell }) || scriptsLoading(names) {
            deferUntilScriptsLoad(cell: cell) { [weak self] in
                self?.attach(
                    cell: cell, references: references, formIDResolver: formIDResolver,
                    firstIntegration: firstIntegration
                )
            }
            return
        }
        retainFormIDResolver(formIDResolver)
        let plan = collectAttachPlan(references: references)
        var attached = attachedByCell[cell] ?? []
        var created: Set<PapyrusInstanceKey> = []
        for item in plan {
            attached.insert(item.key)
            if item.isPersistent {
                persistentKeys.insert(item.key)
            }
            if instancesByKey[item.key] == nil, instantiate(item) {
                created.insert(item.key)
            }
        }
        attachedByCell[cell] = attached
        bind(plan: plan, created: created, formIDResolver: formIDResolver)
        enqueueAttachEvents(
            plan: plan, created: created, firstIntegration: firstIntegration
        )
        if firstIntegration {
            enqueueCellLoad(references: references)
            cellLoadedReferences[cell] = Set(references.sortedEntries().map(\.key))
        }
    }

    /// `OnCellLoad` goes to every script on the cell's references, alias scripts
    /// included, once the cell is in the scene (<https://ck.uesp.net/wiki/OnCellLoad>).
    private func enqueueCellLoad(references: RuntimeReferenceIndex) {
        for entry in references.sortedEntries() {
            for key in instanceKeys(on: entry.key) {
                enqueue(PapyrusScriptEvent(
                    target: key, functionName: Self.onCellLoadEventName, arguments: []
                ))
            }
        }
    }

    /// Retires the cell's instances. Instances whose reference entry was
    /// `isPersistent` survive with their variables intact — including across
    /// world-space transitions, since nothing ever retires them; everything
    /// else is removed from the runtime and from the event queue.
    public func detach(cell: CellSceneLocation) {
        deferredScriptWork.removeAll { $0.cell == cell }
        cellLoadedReferences[cell] = nil
        guard let keys = attachedByCell.removeValue(forKey: cell) else {
            return
        }
        for key in keys.sorted() where !persistentKeys.contains(key) {
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
                    skips.note(.removedScript)
                    continue
                }
                guard resolveScript(named: script.name) else {
                    skips.note(.missingScript)
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
    public func attachUnloaded(
        _ entry: RuntimeReferenceEntry,
        formIDResolver: FormIDResolver
    ) -> Int {
        let names = attachedScripts(of: entry).filter { !$0.isRemoved }.map(\.name)
        guard !names.isEmpty, !scriptsLoading(names) else { return 0 }
        let plan = collectAttachPlan(references: RuntimeReferenceIndex(entries: [entry]))
        var created: Set<PapyrusInstanceKey> = []
        for item in plan {
            persistentKeys.insert(item.key)
            if instancesByKey[item.key] == nil, instantiate(item) {
                created.insert(item.key)
            }
        }
        bind(plan: plan, created: created, formIDResolver: formIDResolver)
        for item in plan where created.contains(item.key) {
            enqueueOnInitIfNeeded(item.key)
        }
        return created.count
    }

    public func instantiate(_ item: PapyrusAttachItem) -> Bool {
        do {
            let handle = try runtime.makeInstance(scriptName: item.script.name)
            instancesByKey[item.key] = handle
            keysByHandle[handle] = item.key
            return true
        } catch {
            skips.note(.instanceCreationFailed)
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
        let handles = referenceHandleMap()
        for item in plan where created.contains(item.key) {
            bind(item, handles: handles, formIDResolver: formIDResolver)
        }
    }

    private func bind(
        _ item: PapyrusAttachItem,
        handles: [ReferenceKey: PapyrusObjectHandle],
        formIDResolver: FormIDResolver
    ) {
        guard
            let handle = instancesByKey[item.key],
            let instance = runtime.instance(for: handle),
            let chain = try? runtime.scriptChain(from: item.script.name)
        else {
            skips.note(.bindingFailed)
            return
        }
        do {
            let binding = try item.script.binding(
                in: runtime,
                formIDResolver: formIDResolver,
                aliases: aliasResolution,
                aliasHandle: { self.aliasInstanceHandle(for: $0) ?? self.objectHandle(for: $0) },
                objectHandle: { handles[$0] ?? self.objectHandle(for: $0) }
            )
            bindingSkips.merge(binding.skipped)
            for (name, value) in binding.initialValues.sorted(by: { $0.key < $1.key })
                where !instance.applyInitialValue(
                    value, named: name, scriptChain: chain
                )
            {
                skips.note(.bindingFailed)
            }
            for setting in binding.propertySettings {
                let outcome = runtime.setProperty(
                    setting.propertyName, on: handle, to: setting.value
                )
                if settle(outcome, target: item.key) {
                    skips.note(.bindingFailed)
                }
            }
        } catch {
            skips.note(.bindingFailed)
        }
    }

    private func enqueueAttachEvents(
        plan: [PapyrusAttachItem],
        created: Set<PapyrusInstanceKey>,
        firstIntegration: Bool
    ) {
        if firstIntegration {
            for item in plan {
                enqueueOnInitIfNeeded(item.key)
                enqueue(PapyrusScriptEvent(
                    target: item.key,
                    functionName: Self.onCellAttachEventName,
                    arguments: []
                ))
                enqueue(PapyrusScriptEvent(
                    target: item.key,
                    functionName: Self.onLoadEventName,
                    arguments: []
                ))
            }
        } else {
            for item in plan where created.contains(item.key) {
                enqueueOnInitIfNeeded(item.key)
            }
        }
    }

    public func retire(_ key: PapyrusInstanceKey) {
        guard let handle = instancesByKey.removeValue(forKey: key) else {
            return
        }
        keysByHandle.removeValue(forKey: handle)
        runtime.instances.removeValue(forKey: handle)
        if let cursor = drainCursor {
            drainCursor = cursor - eventQueue.prefix(cursor).count { $0.target == key }
        }
        eventQueue.removeAll { $0.target == key }
        updateTimers.removeAll(for: key)
        pendingOnInit.remove(key)
        scheduler.cancel(suspensionTracker.forget(instance: key))
    }
}
