// The controls of the Combat & Physics readout and the AI combat section: forced
// attacks and shots, and the combat switches, over the runtimes `CombatShared` holds.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import simd

@MainActor
public final class CombatPanelControls {
    let shared: CombatShared
    var lastMeleeAction = MeleeActionOutcome.idle
    var lastArcheryAction = ArcheryActionOutcome.idle

    init(shared: CombatShared) {
        self.shared = shared
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

    /// The name `residentActors()` gives `key`, so the readouts agree.
    func actorName(_ key: ReferenceKey?) -> String {
        guard let key else { return "—" }
        return shared.world.residentActors().first { $0.key == key }?.name ?? key.description
    }
}
