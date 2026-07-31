// Cell attach and detach for `PapyrusWorldRuntime` (issue #171).
//
// The API takes plain data — a cell location, the cell's reference index, and
// a resolver — so it is testable with synthetic fixtures and carries no
// `CellStreamer` dependency; stage C wires it to streaming.

import Foundation

/// One script slated for instantiation during an attach, in deterministic
/// `sortedEntries()` × VMAD-script order.
nonisolated private struct PapyrusAttachItem {
    let key: PapyrusInstanceKey
    let script: AttachedScript
    let isPersistent: Bool
}

extension PapyrusWorldRuntime {
    /// Instantiates scripts for every reference in `references` that carries
    /// VMAD script data.
    ///
    /// `firstIntegration == false` marks a rebuild: existing instances are
    /// kept and no `OnLoad`/`OnCellAttach` is enqueued. Rebuild edge, decided
    /// here: a reference newly appearing in a rebuilt cell still gets its
    /// instance created and its `OnInit` enqueued (it has never fired), but
    /// no `OnCellAttach`/`OnLoad`, matching the cell not re-attaching.
    ///
    /// Event order on first integration, per instance in sorted order:
    /// `OnInit` (only if never fired) then `OnCellAttach` then `OnLoad` —
    /// enqueued, never dispatched inline.
    func attach(
        cell: CellSceneLocation,
        references: RuntimeReferenceIndex,
        formIDResolver: FormIDResolver,
        firstIntegration: Bool
    ) {
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
    }

    /// Retires the cell's instances. Instances whose reference entry was
    /// `isPersistent` survive with their variables intact — including across
    /// world-space transitions, since nothing ever retires them; everything
    /// else is removed from the runtime and from the event queue.
    func detach(cell: CellSceneLocation) {
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
        entry.placedReference?.scriptData.scripts
            ?? entry.placedActor?.scriptData.scripts
            ?? []
    }

    private func instantiate(_ item: PapyrusAttachItem) -> Bool {
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
    private func bind(
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
                formIDResolver: formIDResolver
            ) { handles[$0] }
            bindingSkips.merge(binding.skipped)
            for (name, value) in binding.initialValues.sorted(by: { $0.key < $1.key })
                where !instance.applyInitialValue(
                    value, named: name, scriptChain: chain
                )
            {
                skips.note(.bindingFailed)
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

    private func retire(_ key: PapyrusInstanceKey) {
        guard let handle = instancesByKey.removeValue(forKey: key) else {
            return
        }
        keysByHandle.removeValue(forKey: handle)
        runtime.instances.removeValue(forKey: handle)
        eventQueue.removeAll { $0.target == key }
        updateTimers.removeAll(for: key)
        pendingOnInit.remove(key)
        busyInstances.remove(key)
        suspensionTracker.forget(instance: key)
    }
}
