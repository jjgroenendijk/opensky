// The readouts and controls of the Combat & Physics readout and the AI combat
// section, read off the runtimes `CombatCoordinator` owns.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import simd

extension CombatCoordinator {
    public var isWeaponDrawn: Bool {
        get { melee?.state.drawState.isWeaponInHand ?? false }
        set { melee?.setWeaponDrawn(newValue) }
    }

    public var meleeCombatSnapshot: MeleeCombatSnapshot {
        guard let melee else { return .unavailable }
        return MeleeCombatSnapshot(
            hitCount: melee.hitCount,
            trace: melee.trace.map(Self.readout)
        )
    }

    @discardableResult
    public func requestMeleeAttack() -> MeleeActionOutcome {
        requestMelee(power: false)
    }

    private func requestMelee(power: Bool) -> MeleeActionOutcome {
        guard let melee else { return .unavailable }
        guard melee.state.drawState.canAttack else {
            lastMeleeAction = .cannotAttack(melee.state.drawState)
            return lastMeleeAction
        }
        if power {
            melee.requestPowerAttack()
        } else {
            melee.requestAttack()
        }
        lastMeleeAction = .requested(power: power)
        return lastMeleeAction
    }

    private static func readout(_ record: MeleeHitRecord) -> MeleeHitReadout {
        MeleeHitReadout(
            target: record.target.description,
            appliedDamage: record.damage.applied
        )
    }
}

extension CombatCoordinator {
    /// Fires through the same `loose` the graph's `arrowRelease` uses, so a
    /// forced shot is the same downstream as a player shot.
    @discardableResult
    public func spawnDevProjectile() -> ArcheryActionOutcome {
        guard let archery else { return .unavailable }
        archery.arrow = selectedArrow()
        guard archery.arrow != nil else {
            lastArcheryAction = .noAmmunition
            return lastArcheryAction
        }
        guard let projectile = archery.loose(consumesArrow: false) else {
            lastArcheryAction = .noLaunchSpeed
            return lastArcheryAction
        }
        lastArcheryAction = .fired(
            id: projectile.id, speed: simd_length(projectile.state.velocity)
        )
        return lastArcheryAction
    }
}

extension CombatCoordinator {
    public var combatLoopSnapshot: CombatLoopSnapshot {
        guard let loop else { return .unavailable }
        var snapshot = CombatLoopSnapshot(
            isPlayerInCombat: loop.state.isPlayerInCombat,
            hostileCount: loop.state.hostileCount,
            actorCastCount: actorCastCount,
            lastActionText: loop.lastAction.text
        )
        snapshot.usesTemperament = usesTemperament
        snapshot.combatAI = combatAI
        snapshot.isInInterior = world.isInInterior
        return snapshot
    }

    /// Reads the persisted Confidence and Assistance and game combat settings switches.
    public func load(settings store: PlayerSettingsStore) {
        usesTemperament = store.bool(.combatTemperament)
        appliesCombatGameSettings = store.bool(.combatGameSettings)
    }

    public var usesCombatTemperament: Bool {
        get { usesTemperament }
        set { usesTemperament = newValue }
    }

    public var selectedActorIsHostile: Bool {
        get {
            guard let loop, let key = world.selectedActor() else { return false }
            return loop.hostility(of: key) == .hostile
        }
        set { setSelectedActorHostile(newValue) }
    }

    public var isActorCastingEnabled: Bool {
        get { allowsActorCasting }
        set { setActorCasting(newValue) }
    }
}
