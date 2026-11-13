// `OnTriggerEnter` / `OnTriggerLeave` dispatch, and the repeating `OnTrigger`, like
// `queueOnActivate` without depth: a trigger edge comes from the streamer's capsule test,
// not script code, so events queue at depth 0. Handlers a script lacks are counted no-ops.

import Foundation
import OpenSkyFormatsESM
public import OpenSkyPhysics
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.ScriptEvents {
    /// Queues `OnTriggerEnter(akActionRef)` on every script instance attached
    /// to `volume`. Returns how many events were queued.
    @discardableResult
    public func queueOnTriggerEnter(volume: ReferenceKey, actor: ReferenceKey) -> Int {
        queueTriggerEvent(PapyrusEngineEvents.onTriggerEnter, volume: volume, actor: actor)
    }

    /// Queues `OnTriggerLeave(akActionRef)` on every script instance attached
    /// to `volume`. Returns how many events were queued.
    @discardableResult
    public func queueOnTriggerLeave(volume: ReferenceKey, actor: ReferenceKey) -> Int {
        queueTriggerEvent(PapyrusEngineEvents.onTriggerLeave, volume: volume, actor: actor)
    }

    /// Instance iteration is in `PapyrusInstanceKey` order, the same
    /// deterministic order `queueOnActivate` uses, so a reference carrying
    /// several scripts always queues them the same way.
    private func queueTriggerEvent(
        _ functionName: String,
        volume: ReferenceKey,
        actor: ReferenceKey
    ) -> Int {
        let handle = world.objectHandle(for: actor)
        var queued = 0
        for key in world.instanceKeys(on: volume) {
            world.enqueue(PapyrusScriptEvent(
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

extension PapyrusWorldStateBridge.Triggers {
    /// `CellStreamer.onTriggerTransition` scripts step: one event per script of the volume's
    /// reference, with the player as `akActionRef`. The event already has a `ReferenceKey`.
    @discardableResult
    public func handleTriggerTransition(_ event: TriggerTransitionEvent) -> Int {
        let actor = event.actor ?? bridge.playerKey
        switch event.phase {
        case .enter:
            bridge.runState.triggerOccupants[event.reference, default: []].insert(actor)
            return bridge.world?.scriptEvents.queueOnTriggerEnter(
                volume: event.reference,
                actor: actor
            ) ?? 0
        case .leave:
            bridge.runState.triggerOccupants[event.reference]?.remove(actor)
            if bridge.runState.triggerOccupants[event.reference]?.isEmpty == true {
                bridge.runState.triggerOccupants[event.reference] = nil
            }
            return bridge.world?.scriptEvents.queueOnTriggerLeave(
                volume: event.reference,
                actor: actor
            ) ?? 0
        }
    }
}

extension PapyrusWorldStateBridge.Triggers {
    /// "Approximately two times a second" while a reference stays inside
    /// (<https://ck.uesp.net/wiki/OnTrigger_-_ObjectReference>).
    public static let triggerRepeatSeconds: Float = 0.5

    /// Queues `OnTrigger(akActionRef)` per occupant once each repeat interval. An instance
    /// that has not run the last one yet gets no new one, so a slow handler cannot pile up.
    @discardableResult
    public func queueTriggerRepeats(after seconds: Float) -> Int {
        guard
            let world = bridge.world, !bridge.runState.triggerOccupants.isEmpty, seconds.isFinite,
            seconds > 0 else { return 0 }
        bridge.runState.triggerRepeatElapsed += seconds
        guard bridge.runState.triggerRepeatElapsed >= Self.triggerRepeatSeconds else { return 0 }
        bridge.runState.triggerRepeatElapsed = bridge.runState.triggerRepeatElapsed
            .truncatingRemainder(dividingBy: Self.triggerRepeatSeconds)
        let name = PapyrusEngineEvents.onTrigger
        let waiting = Set(world.eventQueue.filter { $0.functionName == name }.map(\.target))
        var queued = 0
        for volume in bridge.runState.triggerOccupants.keys.sorted() {
            let actors = (bridge.runState.triggerOccupants[volume] ?? []).sorted()
            for key in world.instanceKeys(on: volume)
                where !waiting.contains(key) && world.scriptEvents.handlesEvent(name, key: key)
            {
                for actor in actors {
                    world.enqueue(PapyrusScriptEvent(
                        target: key, functionName: name,
                        arguments: [.object(world.objectHandle(for: actor))], activationDepth: 0
                    ))
                    queued += 1
                }
            }
        }
        return queued
    }
}
