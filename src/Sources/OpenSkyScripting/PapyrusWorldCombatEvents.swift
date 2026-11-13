// `OnCombatStateChanged(Actor akTarget, int aeCombatState)`
// (<https://ck.uesp.net/wiki/OnCombatStateChanged_-_Actor>), from a per-frame read of each
// scripted actor's combat activity. The combat loop fights the player alone, so the
// target is the player, as `GetCombatTarget` answers.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldStateBridge.CombatEvents {
    /// Queues the event on each instance whose actor's activity changed since the last
    /// call. Returns the count.
    @discardableResult
    public func queueCombatStateEvents() -> Int {
        guard
            let world = bridge.world,
            bridge.natives.actor.combatRuntime?() != nil else { return 0 }
        let name = PapyrusEngineEvents.onCombatStateChanged
        let keys: [PapyrusInstanceKey]
        if let cached = bridge.runState.combatEventKeys, cached.revision == world.instanceRevision {
            keys = cached.keys
        } else {
            keys = world.instancesByKey.keys.filter { world.handlesEvent(name, key: $0) }.sorted()
            bridge.runState.combatEventKeys = (world.instanceRevision, keys)
        }
        var activities: [ReferenceKey: ActorCombatActivity] = [:]
        var queued = 0
        for key in keys {
            guard let activity = activities[key.reference] ?? combatActivity(of: key.reference)
            else { continue }
            activities[key.reference] = activity
            guard activity != bridge.runState.lastCombatActivity[key.reference] ?? .notFighting
            else { continue }
            let target: PapyrusValue = activity == .notFighting || key.reference == .player
                ? .none : .object(world.objectHandle(for: .player))
            world.enqueue(PapyrusScriptEvent(
                target: key, functionName: name,
                arguments: [target, .integer(Int32(activity.rawValue))]
            ))
            queued += 1
        }
        bridge.runState.lastCombatActivity = activities
        return queued
    }
}

extension PapyrusWorldRuntime {
    /// `definesFunction`, remembered per instance: a script chain does not change while
    /// the instance lives, and a per-frame scan asks the same question every frame.
    func handlesEvent(_ name: String, key: PapyrusInstanceKey) -> Bool {
        if let known = handledEvents[key]?[name] {
            return known
        }
        let answer = definesFunction(name, key: key)
        handledEvents[key, default: [:]][name] = answer
        return answer
    }
}
