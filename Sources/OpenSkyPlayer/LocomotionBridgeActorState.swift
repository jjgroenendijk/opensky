// The actor-state inputs of one step, written to both graphs through `write(_:to:)`, and
// the `iState_*` constants read back to encode `iState`.

import Foundation
import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyPhysics

nonisolated extension LocomotionBridge {
    func writeActorState(gait: LocomotionGait) {
        guard isPlayerGraph else { return }
        actorState.swimming = gait == .swim
        let state = ActorStateGraphCore.state(for: actorState, gait: gait)
        let writes = ActorStateGraphCore.writes(
            actorState,
            sprintAllowed: isSprintAllowed,
            wantsBlock: meleeIntent.block,
            stateValue: actorStateConstants[state]
        )
        for (name, value) in writes where name != ActorStateGraphNames.combatStance
            || declaresCombatStance
        {
            write(value, to: name)
        }
        wasCombatStance = actorState.weaponDrawn
    }

    /// Only the horse graphs read `iCombatStance`; a character graph is not told it.
    private var declaresCombatStance: Bool {
        [graph, firstPersonGraph].contains {
            $0?.variable(named: ActorStateGraphNames.combatStance) != nil
        }
    }

    /// The value of each `iState_*` constant the graph declares. The third-person
    /// graph holds them; the first-person one stands in when it is the only one.
    public var actorStateConstants: [ActorGraphState: Int32] {
        guard let source = graph ?? firstPersonGraph else { return [:] }
        var constants: [ActorGraphState: Int32] = [:]
        for state in ActorGraphState.allCases {
            if let value = source.variable(named: state.variableName) {
                constants[state] = Int32(truncatingIfNeeded: value.intValue)
            }
        }
        return constants
    }
}
