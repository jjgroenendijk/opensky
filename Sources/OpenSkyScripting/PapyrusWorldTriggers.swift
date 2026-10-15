// `OnTriggerEnter` / `OnTriggerLeave` dispatch, and the repeating `OnTrigger`, like
// `queueOnActivate` without depth: a trigger edge comes from the streamer's capsule test,
// not script code, so events queue at depth 0. Handlers a script lacks are counted no-ops.

import Foundation
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
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
        let handle = objectHandle(for: actor)
        var queued = 0
        for key in instanceKeys(on: volume) {
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
        let actor = event.actor ?? playerKey
        switch event.phase {
        case .enter:
            triggerOccupants[event.reference, default: []].insert(actor)
            return world?.queueOnTriggerEnter(volume: event.reference, actor: actor) ?? 0
        case .leave:
            triggerOccupants[event.reference]?.remove(actor)
            if triggerOccupants[event.reference]?.isEmpty == true {
                triggerOccupants[event.reference] = nil
            }
            return world?.queueOnTriggerLeave(volume: event.reference, actor: actor) ?? 0
        }
    }
}

extension PapyrusWorldStateBridge {
    /// "Approximately two times a second" while a reference stays inside
    /// (<https://ck.uesp.net/wiki/OnTrigger_-_ObjectReference>).
    public static let triggerRepeatSeconds: Float = 0.5

    /// Queues `OnTrigger(akActionRef)` per occupant once each repeat interval. An instance
    /// that has not run the last one yet gets no new one, so a slow handler cannot pile up.
    @discardableResult
    public func queueTriggerRepeats(after seconds: Float) -> Int {
        guard let world, !triggerOccupants.isEmpty, seconds.isFinite, seconds > 0 else { return 0 }
        triggerRepeatElapsed += seconds
        guard triggerRepeatElapsed >= Self.triggerRepeatSeconds else { return 0 }
        triggerRepeatElapsed = triggerRepeatElapsed
            .truncatingRemainder(dividingBy: Self.triggerRepeatSeconds)
        let name = PapyrusEngineEvents.onTrigger
        let waiting = Set(world.eventQueue.filter { $0.functionName == name }.map(\.target))
        var queued = 0
        for volume in triggerOccupants.keys.sorted() {
            let actors = (triggerOccupants[volume] ?? []).sorted()
            for key in world.instanceKeys(on: volume)
                where !waiting.contains(key) && world.handlesEvent(name, key: key)
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
