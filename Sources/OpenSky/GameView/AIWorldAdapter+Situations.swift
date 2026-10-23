// The situations that pick an actor's override package list, and a guard's warning.
// The rules live in `PackageSituationScan` and the Guard procedure
// (docs/engine/package-schedules.md, "Package lists").

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCombat
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

extension AIWorldAdapter {
    /// The graph events that draw and sheathe the weapon.
    static let drawWeaponEvent = "WeapEquip"
    static let sheatheWeaponEvent = "Unequip"

    /// An actor whose combat override package runs is held out of the fight, so it
    /// still counts as fighting while it stays hostile.
    func packageSituations(of actors: [ReferenceKey]) -> [ReferenceKey: PackageSituation] {
        let loop = game.combat.loop
        let observations = game.actorWorld.combatActors().map { actor in
            let engaged = loop?.phase(of: actor.key)?.isEngaged == true
            let held = game.packages.runtime?.source(for: actor.key) == .situation(.combat)
                && game.combat.combatHostility(of: actor.key) == .hostile
            return PackageSituationObservation(
                key: actor.key, position: actor.feet, isDead: actor.isDead,
                isFighting: !actor.isDead && (engaged || held)
            )
        }
        return PackageSituationScan.situations(of: actors, observations: observations)
    }

    /// The guard draws its weapon and says a trespass line, when the load order has one
    /// it may say now. Without one the warning still counts.
    func warn(_ intruder: ReferenceKey, from guardKey: ReferenceKey) -> PackageActionResult {
        _ = game.actorGraphWorld.graphs.raise(Self.drawWeaponEvent, on: guardKey)
        guard
            let seconds = game.storyWorld.sayTopic("TRES", speaker: guardKey, lookAt: intruder)
        else { return .done }
        return .lasts(seconds: seconds)
    }

    func standDown(_ guardKey: ReferenceKey) -> PackageActionResult {
        _ = game.actorGraphWorld.graphs.raise(Self.sheatheWeaponEvent, on: guardKey)
        return .done
    }
}
