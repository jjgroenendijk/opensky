// Activation events and world object handles for `PapyrusWorldRuntime`: one
// `OnActivate` per attached script, and handles for unscripted references, which is how
// the player (no record, no VMAD) can be an `akActionRef`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Queues `OnActivate(akActionRef)` on each script of `target`, in
    /// `PapyrusInstanceKey` order, with the activator as argument 0. No scripts is not
    /// an error. Depth is `currentActivationDepth + 1`; a chain past
    /// `maximumActivationDepth` is tallied.
    @discardableResult
    public func queueOnActivate(
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

    /// The session-stable handle for `key`: its live instance handle when scripted, else
    /// an opaque handle that `PapyrusInterpreter` dispatches by declared type. A reference
    /// scripted later keeps both handles; both resolve to the same `ReferenceKey`.
    public func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle {
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
    public func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
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
