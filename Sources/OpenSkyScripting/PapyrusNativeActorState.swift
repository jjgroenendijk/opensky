// `Actor` natives over the combat loop and the script state: `GetCombatState`,
// `GetCombatTarget`, `StopCombatAlarm`, `EnableAI`, and the reads OpenSky answers from
// what it does not simulate. Signatures are from <https://ck.uesp.net/wiki/Actor_Script>.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkyWorldState

extension PapyrusNativeFunctions {
    static let aiDisabledName = "aiDisabled"

    public static func installActorState(into registry: inout PapyrusNativeRegistry) {
        // `int GetCombatState()`: 0 not in combat, 1 in combat, 2 searching, which are
        // the raw values of `ActorCombatActivity`.
        scriptState("Actor", "GetCombatState", into: &registry) { call, bridge, key in
            guard let activity = bridge.combatActivity(of: key) else {
                return failure(call, "GetCombatState needs a combat runtime")
            }
            return .returned(.integer(Int32(activity.rawValue)))
        }
        // OpenSky's combat loop fights the player alone, so a fighting actor targets
        // the player, and the player has no target.
        scriptState("Actor", "GetCombatTarget", into: &registry) { call, bridge, key in
            guard let activity = bridge.combatActivity(of: key) else {
                return failure(call, "GetCombatTarget needs a combat runtime")
            }
            guard activity != .notFighting, key != .player else { return .returned(.none) }
            return .returned(handle(.player, in: bridge))
        }
        // `StopCombatAlarm()` ends the actor's fight; OpenSky keeps no alarm apart from it.
        scriptState("Actor", "StopCombatAlarm", into: &registry) { _, bridge, key in
            bridge.stopActorCombat(key)
            return .returned(.none)
        }
        // `EnableAI(bool abEnable = true)` and `bool IsAIEnabled()`.
        scriptState("Actor", "EnableAI", into: &registry) { call, bridge, key in
            let enabled = boolean(call, at: 0, default: true)
            bridge.updateScriptedState(of: key) { $0.setFlag(aiDisabledName, enabled ? nil : true) }
            return .returned(.none)
        }
        scriptState("Actor", "IsAIEnabled", into: &registry) { _, bridge, key in
            .returned(.boolean(bridge.scriptedState(of: key).flag(aiDisabledName) != true))
        }
        // OpenSky has no bleedout and no commanded actors, so nobody is either.
        for name in ["IsBleedingOut", "IsCommandedActor"] {
            scriptState("Actor", name, into: &registry) { _, _, _ in .returned(.boolean(false)) }
        }
        // `AddAchievement(int)`: OpenSky reports to no platform, so nothing happens.
        registry.register(PapyrusNativeFunction(
            scriptName: "Game", functionName: "AddAchievement"
        ) { _, _ in .returned(.none) })
    }
}

extension PapyrusWorldStateBridge {
    /// Nil without a combat runtime. A dead actor is not fighting.
    func combatActivity(of key: ReferenceKey) -> ActorCombatActivity? {
        guard let combat = actorNatives.combatRuntime?() else { return nil }
        guard worldState.component(ActorDeathState.self, for: key)?.isDead != true else {
            return .notFighting
        }
        return combat.activity(of: key)
    }
}
