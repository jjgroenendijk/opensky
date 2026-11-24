// What the help rule asks of the session: the follower flag scripts set, and the crime
// state. See docs/engine/combat.md#who-an-assisting-actor-fights.

public import OpenSkyCombat
import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkySessionInterface

extension CombatReportsAdapter {
    public func isPlayerTeammate(_ key: ReferenceKey) -> Bool {
        game.scripts.bridge?.scriptedState(of: key).flag(ScriptedStateName.playerTeammate) == true
    }

    public func crimeStanding(
        of actor: ReferenceKey, judgedBy helper: ReferenceKey
    ) -> CombatCrimeStanding {
        switch game.crime.assistStanding(of: actor, judgedBy: helper) {
        case .clean: .clean
        case .criminal: .criminal
        case .criminalWhileAGuardFights: .criminalWhileAGuardFights
        }
    }

    public func isGuard(_ key: ReferenceKey) -> Bool {
        game.crime.isGuard(key)
    }

    public func attacksPlayerOnSightForCrimes(_ key: ReferenceKey) -> Bool {
        game.crime.attacksPlayerOnSightForCrimes(key)
    }
}
