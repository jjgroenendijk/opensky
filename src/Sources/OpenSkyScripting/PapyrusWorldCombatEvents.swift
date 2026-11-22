// `OnCombatStateChanged(Actor akTarget, int aeCombatState)`
// (<https://ck.uesp.net/wiki/OnCombatStateChanged_-_Actor>), from a per-frame read of each
// scripted actor's combat activity. The combat loop fights the player alone, so the
// target is the player, as `GetCombatTarget` answers.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusWorldStateBridge.CombatEvents {
    /// Queues the event on each instance whose actor's activity changed since the last
    /// call. Returns the count.
    @discardableResult
    public func queueCombatStateEvents() -> Int {
        guard
            let world = bridge.world,
            let combat = bridge.natives.actor.combatRuntime?() else { return 0 }
        // The player fights while any actor fights. With nobody fighting now and
        // nobody last time, no instance can have changed.
        if
            bridge.runState.lastCombatActivity.isEmpty,
            combat.activity(of: .player) == .notFighting
        {
            return 0
        }
        let name = PapyrusEngineEvents.onCombatStateChanged
        let keys: [PapyrusInstanceKey]
        if let cached = bridge.runState.combatEventKeys, cached.revision == world.instanceRevision {
            keys = cached.keys
        } else {
            keys = world.instancesByKey.keys
                .filter { world.scriptEvents.handlesEvent(name, key: $0) }.sorted()
            bridge.runState.combatEventKeys = (world.instanceRevision, keys)
        }
        // Only an actor that fights or searches is kept; a missing entry reads as not fighting.
        var activities: [ReferenceKey: ActorCombatActivity] = [:]
        var queued = 0
        for key in keys {
            let isDead = bridge.worldState
                .component(ActorDeathState.self, for: key.reference)?.isDead == true
            let activity = activities[key.reference]
                ?? (isDead ? .notFighting : combat.activity(of: key.reference))
            if activity != .notFighting {
                activities[key.reference] = activity
            }
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

extension PapyrusWorldRuntime.ScriptEvents {
    /// `definesFunction`, remembered per instance: a script chain does not change while
    /// the instance lives, and a per-frame scan asks the same question every frame.
    func handlesEvent(_ name: String, key: PapyrusInstanceKey) -> Bool {
        if let known = world.handledEvents[key]?[name] {
            return known
        }
        let answer = definesFunction(name, key: key)
        world.handledEvents[key, default: [:]][name] = answer
        return answer
    }
}
