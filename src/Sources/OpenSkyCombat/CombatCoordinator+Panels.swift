// The readouts of the Combat & Physics readout and the AI combat section, read off
// the runtimes `CombatCoordinator` owns.

import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyFormatsESM

extension CombatCoordinator {
    public var isWeaponDrawn: Bool {
        get { shared.melee?.isWeaponInHand ?? false }
        set { shared.melee?.setWeaponDrawn(newValue) }
    }

    public var meleeCombatSnapshot: MeleeCombatSnapshot {
        MeleeCombatSnapshot(melee: shared.melee)
    }

    public var combatLoopSnapshot: CombatLoopSnapshot {
        CombatLoopSnapshot(shared: shared)
    }
}

extension MeleeCombatRuntime {
    var isWeaponInHand: Bool {
        state.drawState.isWeaponInHand
    }
}

extension MeleeCombatSnapshot {
    /// The hit count and trace, or `.unavailable` without game data.
    @MainActor
    init(melee: MeleeCombatRuntime?) {
        guard let melee else {
            self = .unavailable
            return
        }
        self.init(hitCount: melee.hitCount, trace: melee.trace.map(Self.readout))
    }

    private static func readout(_ record: MeleeHitRecord) -> MeleeHitReadout {
        MeleeHitReadout(
            target: record.target.description,
            appliedDamage: record.damage.applied
        )
    }
}

@MainActor
extension CombatLoopSnapshot {
    init(shared: CombatShared) {
        guard let loop = shared.loop else {
            self = .unavailable
            return
        }
        self.init(
            isPlayerInCombat: loop.state.isPlayerInCombat,
            hostileCount: loop.state.hostileCount,
            actorCastCount: shared.actorCastCount,
            lastActionText: loop.lastAction.text
        )
        usesTemperament = shared.usesTemperament
        combatAI = shared.combatAI
        isInInterior = shared.world.isInInterior
    }
}
