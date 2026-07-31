// `OnTriggerEnter` / `OnTriggerLeave` dispatch (issue #173).
//
// Structurally this is `queueOnActivate` from PapyrusWorldActivation.swift
// minus the activation-depth machinery. A trigger edge is not an activation
// chain: nothing in it can queue another trigger edge, because occupancy comes
// from the streamer's per-frame capsule test and not from script code. So the
// events are queued at depth 0 and never consume the recursion cap, which
// would otherwise be spent by a player standing in a volume that activates
// something.
//
// A script attached to a volume that does not implement the handler is a
// counted no-op (`undefinedEventFunction`), not a fault, so queuing on every
// script of the authoring reference is both free and correct.

import Foundation

extension PapyrusWorldRuntime {
    /// Queues `OnTriggerEnter(akActionRef)` on every script instance attached
    /// to `volume`. Returns how many events were queued.
    @discardableResult
    func queueOnTriggerEnter(volume: ReferenceKey, actor: ReferenceKey) -> Int {
        queueTriggerEvent(Self.onTriggerEnterEventName, volume: volume, actor: actor)
    }

    /// Queues `OnTriggerLeave(akActionRef)` on every script instance attached
    /// to `volume`. Returns how many events were queued.
    @discardableResult
    func queueOnTriggerLeave(volume: ReferenceKey, actor: ReferenceKey) -> Int {
        queueTriggerEvent(Self.onTriggerLeaveEventName, volume: volume, actor: actor)
    }

    /// Instance iteration is `instancesByKey.keys.sorted()`, the same
    /// deterministic order `queueOnActivate` uses, so a reference carrying
    /// several scripts always queues them the same way.
    private func queueTriggerEvent(
        _ functionName: String,
        volume: ReferenceKey,
        actor: ReferenceKey
    ) -> Int {
        let handle = objectHandle(for: actor)
        var queued = 0
        for key in instancesByKey.keys.sorted() where key.reference == volume {
            enqueue(PapyrusScriptEvent(
                target: key,
                functionName: functionName,
                arguments: [.object(handle)],
                activationDepth: 0
            ))
            queued += 1
        }
        return queued
    }
}

extension PapyrusWorldStateBridge {
    /// `CellStreamer.onTriggerTransition` subscriber: one occupancy edge
    /// becomes one queued event per script attached to the volume's authoring
    /// reference, with the player as `akActionRef`.
    ///
    /// The event already carries a `ReferenceKey`, so unlike
    /// `handleInteraction(_:)` there is no FormID to resolve — the trigger
    /// build took the key from the cell's runtime index and skipped any volume
    /// it could not name.
    @discardableResult
    func handleTriggerTransition(_ event: TriggerTransitionEvent) -> Int {
        guard let world else { return 0 }
        switch event.phase {
        case .enter:
            return world.queueOnTriggerEnter(volume: event.reference, actor: playerKey)
        case .leave:
            return world.queueOnTriggerLeave(volume: event.reference, actor: playerKey)
        }
    }
}
