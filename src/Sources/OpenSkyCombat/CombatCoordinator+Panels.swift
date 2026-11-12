// The readouts and controls of the Combat & Physics readout and the AI combat
// section, read off the runtimes `CombatCoordinator` owns.

import Foundation
import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import simd

extension CombatCoordinator {
    public var isWeaponDrawn: Bool {
        get { shared.melee?.state.drawState.isWeaponInHand ?? false }
        set { shared.melee?.setWeaponDrawn(newValue) }
    }

    public var meleeCombatSnapshot: MeleeCombatSnapshot {
        guard let melee = shared.melee else { return .unavailable }
        return MeleeCombatSnapshot(
            hitCount: melee.hitCount,
            trace: melee.trace.map(Self.readout)
        )
    }

    @discardableResult
    func requestMeleeAttack() -> MeleeActionOutcome {
        requestMelee(power: false)
    }

    private func requestMelee(power: Bool) -> MeleeActionOutcome {
        guard let melee = shared.melee else { return .unavailable }
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
    func spawnDevProjectile() -> ArcheryActionOutcome {
        guard let archery = shared.archery else { return .unavailable }
        archery.arrow = shared.gear.selectedArrow()
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
        guard let loop = shared.loop else { return .unavailable }
        var snapshot = CombatLoopSnapshot(
            isPlayerInCombat: loop.state.isPlayerInCombat,
            hostileCount: loop.state.hostileCount,
            actorCastCount: shared.actorCastCount,
            lastActionText: loop.lastAction.text
        )
        snapshot.usesTemperament = shared.usesTemperament
        snapshot.combatAI = shared.combatAI
        snapshot.isInInterior = shared.world.isInInterior
        return snapshot
    }

    /// Reads the persisted Confidence and Assistance and game combat settings switches.
    public func load(settings store: PlayerSettingsStore) {
        shared.usesTemperament = store.bool(.combatTemperament)
        shared.appliesCombatGameSettings = store.bool(.combatGameSettings)
        shared.loop?.applyingGameSettings = shared.appliesCombatGameSettings
    }

    var usesCombatTemperament: Bool {
        get { shared.usesTemperament }
        set { shared.usesTemperament = newValue }
    }

    var selectedActorIsHostile: Bool {
        get {
            guard
                let loop = shared.loop,
                let key = shared.world.selectedActor() else { return false }
            return loop.hostility(of: key) == .hostile
        }
        set { setSelectedActorHostile(newValue) }
    }

    var isActorCastingEnabled: Bool {
        get { shared.allowsActorCasting }
        set { setActorCasting(newValue) }
    }
}

extension CombatCoordinator {
    /// Turning casting off drops every cast in flight, so no charge is left
    /// that nothing will release.
    func setActorCasting(_ allowed: Bool) {
        shared.allowsActorCasting = allowed
        guard !allowed, let loop = shared.loop else { return }
        for key in loop.behaviors.keys.sorted() {
            shared.world.cancelCast(by: key)
        }
        loop.record(.castingDisallowed)
    }

    /// Sets hostility on the readout's selected actor and records the outcome.
    func setSelectedActorHostile(_ hostile: Bool) {
        guard let loop = shared.loop else { return }
        guard let key = shared.world.selectedActor() else {
            loop.record(.noHostilityTarget)
            return
        }
        loop.setHostility(hostile ? .hostile : .neutral, on: key)
        loop.record(.hostility(actor: actorName(key), hostile: hostile))
    }
}
