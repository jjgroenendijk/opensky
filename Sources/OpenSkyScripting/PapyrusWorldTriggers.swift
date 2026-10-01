// `OnTriggerEnter` / `OnTriggerLeave` dispatch, like `queueOnActivate` without depth: a
// trigger edge comes from the streamer's capsule test, not script code, so events queue
// at depth 0. Handlers a script lacks are counted no-ops.

import Foundation
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Queues `OnTriggerEnter(akActionRef)` on every script instance attached
    /// to `volume`. Returns how many events were queued.
    @discardableResult
    public func queueOnTriggerEnter(volume: ReferenceKey, actor: ReferenceKey) -> Int {
        queueTriggerEvent(Self.onTriggerEnterEventName, volume: volume, actor: actor)
    }

    /// Queues `OnTriggerLeave(akActionRef)` on every script instance attached
    /// to `volume`. Returns how many events were queued.
    @discardableResult
    public func queueOnTriggerLeave(volume: ReferenceKey, actor: ReferenceKey) -> Int {
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
    /// `CellStreamer.onTriggerTransition` subscriber: one event per script of the volume's
    /// reference, with the player as `akActionRef`. The event already has a `ReferenceKey`.
    @discardableResult
    public func handleTriggerTransition(_ event: TriggerTransitionEvent) -> Int {
        guard let world else { return 0 }
        let actor = event.actor ?? playerKey
        switch event.phase {
        case .enter:
            return world.queueOnTriggerEnter(volume: event.reference, actor: actor)
        case .leave:
            return world.queueOnTriggerLeave(volume: event.reference, actor: actor)
        }
    }
}
