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
        for key in instanceKeys(on: target) {
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
    /// whole map. Alias scripts are not `ObjectReference` scripts, so they never answer.
    private func instanceHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        let aliasKeys = aliasInstanceKeys
        return instancesByKey.keys
            .filter { $0.reference == key && !aliasKeys.contains($0) }
            .min()
            .flatMap { instancesByKey[$0] }
    }

    /// The lowest-script-name alias script on a filled reference, which an alias-typed
    /// property binds to, so the alias script's own functions resolve.
    func aliasInstanceHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        aliasInstanceKeys.filter { $0.reference == key }.min().flatMap { instancesByKey[$0] }
    }

    /// The lowest-script-name instance on the same form as `handle` whose script is
    /// `typeName` or extends it. An alias script and a form script never pair.
    /// An opaque handle of a stopped quest or an unloaded reference attaches its
    /// scripts first, as they exist in the game (`attachOnUse`).
    func sibling(of handle: PapyrusObjectHandle, as typeName: String) -> PapyrusObjectHandle? {
        guard let reference = referenceKey(for: handle) else { return nil }
        let aliasKeys = aliasInstanceKeys
        let isAlias = keysByHandle[handle].map(aliasKeys.contains) ?? false
        let find = {
            self.instancesByKey.keys
                .filter { $0.reference == reference && aliasKeys.contains($0) == isAlias }
                .sorted()
                .lazy
                .compactMap { self.instancesByKey[$0] }
                .first { self.runtime.resolvesObject($0, as: typeName) }
        }
        if let found = find() {
            return found
        }
        guard keysByHandle[handle] == nil, attachOnUse?(reference) == true else { return nil }
        return find()
    }

    var aliasInstanceKeys: Set<PapyrusInstanceKey> {
        questAliasInstanceKeys.values.reduce(into: []) { $0.formUnion($1) }
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
