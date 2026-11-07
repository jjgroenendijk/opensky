// What the engine records on a form as it happens, for the conditions that ask later:
// who killed an actor, friendly hits by the player, and the last actor that attacked
// the player. See docs/engine/condition-functions-world.md#recorded-events.

import Foundation
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldStateBridge {
    /// `IsKiller` reads the link on the victim. A death with no known killer clears it.
    public func recordKill(victim: ReferenceKey, killer: ReferenceKey?) {
        updateScriptedState(of: victim) { $0.setForm(ScriptedStateName.killer, killer) }
    }

    /// A location the game cleared itself, after its last boss died: the flag
    /// `IsCleared` reads, the HUD notice, and the music when `playsMusic`.
    public func markLocationCleared(_ location: ReferenceKey, playsMusic: Bool) {
        guard scriptedState(of: location).flag(ScriptedStateName.cleared) != true else { return }
        updateScriptedState(of: location) { $0.setFlag(ScriptedStateName.cleared, true) }
        if let name = formName(of: location) {
            presenter?.postWorldNotice(.locationCleared(name: name, playsMusic: playsMusic))
        }
    }

    /// A blow by the player on an actor that was not hostile counts for `GetFriendHit`.
    /// A blow on the player names its aggressor for `IsLastHostileActor`.
    public func recordHit(_ hit: ScriptHitEvent, targetWasHostile: Bool) {
        if hit.aggressor == .player, hit.target != .player, !targetWasHostile {
            updateScriptedState(of: hit.target) { state in
                let hits = state.value(ScriptedStateName.friendHits) ?? 0
                state.setValue(ScriptedStateName.friendHits, hits + 1)
            }
        }
        if hit.target == .player, hit.aggressor != .player {
            updateScriptedState(of: .player) {
                $0.setForm(ScriptedStateName.lastHostileActor, hit.aggressor)
            }
        }
    }
}
