// Activation events and world object handles for `PapyrusWorldRuntime`
// (issue #172).
//
// Two jobs, both about naming world things from script code:
//
// * `OnActivate` queuing, one event per script attached to the activated
//   reference, with `akActionRef` as argument 0.
// * Object handles for references that carry no script instance, which is the
//   only way the player — no plugin record, no VMAD — can be an `akActionRef`
//   at all.

import Foundation

extension PapyrusWorldRuntime {
    /// Queues `OnActivate(akActionRef)` on every script instance attached to
    /// `target`, in `PapyrusInstanceKey` order so the queue is deterministic.
    ///
    /// The activator becomes argument 0 as `PapyrusValue.object(handle)`,
    /// matching `OnActivate(ObjectReference akActionRef)`. A target with no
    /// attached scripts queues nothing and is not an error: recording the
    /// activation in `WorldStateStore` is the caller's job and happens either
    /// way.
    ///
    /// The events inherit depth `currentActivationDepth + 1`, and a chain that
    /// would exceed `maximumActivationDepth` queues nothing and is tallied.
    @discardableResult
    func queueOnActivate(
        target: ReferenceKey,
        activator: ReferenceKey
    ) -> PapyrusActivationOutcome {
        let depth = currentActivationDepth + 1
        guard depth <= Self.maximumActivationDepth else {
            runtime.tally.noteActivationRecursionCapped()
            return PapyrusActivationOutcome(
                recorded: false, queuedEvents: 0, cappedByRecursion: true
            )
        }
        let handle = objectHandle(for: activator)
        var queued = 0
        for key in instancesByKey.keys.sorted() where key.reference == target {
            enqueue(PapyrusScriptEvent(
                target: key,
                functionName: Self.onActivateEventName,
                arguments: [.object(handle)],
                activationDepth: depth
            ))
            queued += 1
        }
        return PapyrusActivationOutcome(
            recorded: false, queuedEvents: queued, cappedByRecursion: false
        )
    }

    /// The handle that names `key` in script code, stable for the session.
    ///
    /// A reference carrying scripts answers with its live instance handle —
    /// the same one `referenceHandleMap()` binds VMAD object properties to, so
    /// a method call on it dispatches into the script. Anything else, the
    /// player included, gets an opaque handle with no instance behind it;
    /// `PapyrusInterpreter` routes method calls on such a handle through the
    /// operand's declared type, which is how `ObjectReference` natives still
    /// resolve.
    ///
    /// Stated edge: a reference that gains a script instance after an opaque
    /// handle was handed out keeps both handles alive. Both resolve back to
    /// the same `ReferenceKey`, so world writes stay correct; only handle
    /// identity comparison in script code would notice.
    func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle {
        if let existing = instanceHandle(for: key) {
            return existing
        }
        if let existing = opaqueHandlesByKey[key] {
            return existing
        }
        let handle = allocateOpaqueHandle()
        opaqueHandlesByKey[key] = handle
        opaqueKeysByHandle[handle] = key
        return handle
    }

    /// World identity behind a handle: a live script instance's reference, or
    /// the reference an opaque handle was minted for. Nil for a handle this
    /// world runtime never handed out.
    func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        keysByHandle[handle]?.reference ?? opaqueKeysByHandle[handle]
    }

    /// Lowest-script-name instance handle for a reference, matching
    /// `referenceHandleMap()`'s deterministic choice without building the
    /// whole map.
    private func instanceHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        instancesByKey.keys
            .filter { $0.reference == key }
            .min()
            .flatMap { instancesByKey[$0] }
    }

    private func allocateOpaqueHandle() -> PapyrusObjectHandle {
        while
            opaqueKeysByHandle[PapyrusObjectHandle(nextOpaqueHandleValue)] != nil
            || runtime.instance(for: PapyrusObjectHandle(nextOpaqueHandleValue)) != nil
        {
            nextOpaqueHandleValue &-= 1
        }
        defer { nextOpaqueHandleValue &-= 1 }
        return PapyrusObjectHandle(nextOpaqueHandleValue)
    }
}
