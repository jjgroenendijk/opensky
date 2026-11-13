// Activation events and world object handles for `PapyrusWorldRuntime`: one
// `OnActivate` per attached script, and handles for unscripted references, which is how
// the player (no record, no VMAD) can be an `akActionRef`.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.ActivationRuns {
    /// Queues `OnActivate(akActionRef)` on each script of `target`, in
    /// `PapyrusInstanceKey` order, with the activator as argument 0. No scripts is not
    /// an error. Depth is `currentActivationDepth + 1`; a chain past
    /// `maximumActivationDepth` is tallied.
    @discardableResult
    func queueOnActivate(
        target: ReferenceKey,
        activator: ReferenceKey
    ) -> PapyrusActivationOutcome {
        let depth = world.currentActivationDepth + 1
        guard depth <= PapyrusWorldRuntime.maximumActivationDepth else {
            world.runtime.tally.noteActivationRecursionCapped()
            return PapyrusActivationOutcome(
                recorded: false, queuedEvents: 0, cappedByRecursion: true
            )
        }
        let handle = objectHandle(for: activator)
        var queued = 0
        for key in world.instanceKeys(on: target) {
            world.enqueue(PapyrusScriptEvent(
                target: key,
                functionName: PapyrusEngineEvents.onActivate,
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
    /// an opaque handle that `PapyrusRuntime.Interpreter` dispatches by declared type. A reference
    /// scripted later keeps both handles; both resolve to the same `ReferenceKey`.
    public func objectHandle(for key: ReferenceKey) -> PapyrusObjectHandle {
        if let existing = instanceHandle(for: key) {
            return existing
        }
        if let existing = world.opaqueHandlesByKey[key] {
            return existing
        }
        let handle = allocateOpaqueHandle()
        world.opaqueHandlesByKey[key] = handle
        world.opaqueKeysByHandle[handle] = key
        return handle
    }

    /// World identity behind a handle: a live script instance's reference, or
    /// the reference an opaque handle was minted for. Nil for a handle this
    /// world runtime never handed out.
    public func referenceKey(for handle: PapyrusObjectHandle) -> ReferenceKey? {
        world.keysByHandle[handle]?.reference ?? world.opaqueKeysByHandle[handle]
            ?? world.aliasSlotsByHandle[handle].flatMap(world.questRuns.aliasReference(in:))
    }

    /// Lowest-script-name instance handle for a reference, matching
    /// `referenceHandleMap()`'s deterministic choice without building the
    /// whole map. Alias and effect scripts are not `ObjectReference` scripts, so they never answer.
    private func instanceHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        let otherKeys = aliasInstanceKeys.union(world.effectScripts.instanceKeys)
        return world.instanceKeys(on: key)
            .first { !otherKeys.contains($0) }
            .flatMap { world.instancesByKey[$0] }
    }

    /// The lowest-script-name alias script on a filled reference, which an alias-typed
    /// property binds to, so the alias script's own functions resolve.
    func aliasInstanceHandle(for key: ReferenceKey) -> PapyrusObjectHandle? {
        aliasInstanceKeys.filter { $0.reference == key }.min().flatMap { world.instancesByKey[$0] }
    }

    /// The lowest-script-name instance on the same form as `handle` whose script is
    /// `typeName` or extends it. An alias script and a form script never pair.
    /// An opaque handle of a stopped quest or an unloaded reference attaches its
    /// scripts first, as they exist in the game (`attachOnUse`).
    func sibling(of handle: PapyrusObjectHandle, as typeName: String) -> PapyrusObjectHandle? {
        if let slot = world.aliasSlotsByHandle[handle] {
            return world.questRuns.aliasInstance(of: slot, as: typeName)
        }
        guard let reference = referenceKey(for: handle) else { return nil }
        let group = world.keysByHandle[handle].map(instanceGroup) ?? .form
        let find = {
            world.instanceKeys(on: reference)
                .filter { self.instanceGroup($0) == group }
                .lazy
                .compactMap { world.instancesByKey[$0] }
                .first { world.runtime.resolvesObject($0, as: typeName) }
        }
        if let found = find() {
            return found
        }
        guard
            world.keysByHandle[handle] == nil,
            world.attachOnUse?(reference) == true else { return nil }
        return find()
    }

    /// Form, alias, and magic effect scripts on one reference never pair as siblings.
    func instanceGroup(_ key: PapyrusInstanceKey) -> PapyrusInstanceGroup {
        if world.effectScripts.contains(instance: key) {
            return .effect
        }
        return aliasInstanceKeys.contains(key) ? .alias : .form
    }

    var aliasInstanceKeys: Set<PapyrusInstanceKey> {
        if let aliasInstanceKeysCache = world.aliasInstanceKeysCache {
            return aliasInstanceKeysCache
        }
        let keys = world.questAliasInstanceKeys.values
            .reduce(into: Set<PapyrusInstanceKey>()) { $0.formUnion($1) }
        world.aliasInstanceKeysCache = keys
        return keys
    }

    func allocateOpaqueHandle() -> PapyrusObjectHandle {
        while
            world.opaqueKeysByHandle[PapyrusObjectHandle(world.nextOpaqueHandleValue)] != nil
            || world.runtime.instance(for: PapyrusObjectHandle(world.nextOpaqueHandleValue)) != nil
        {
            world.nextOpaqueHandleValue &-= 1
        }
        defer { world.nextOpaqueHandleValue &-= 1 }
        return PapyrusObjectHandle(world.nextOpaqueHandleValue)
    }
}

/// What kind of script an instance on a reference is.
enum PapyrusInstanceGroup {
    case form
    case alias
    case effect
}
