public import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DragonFlightCandidatesAdapter` reads from the session.
@MainActor
public protocol DragonFlightCandidatesHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var combatWorld: any CombatWorldPort { get }
    var mounts: any MountPort { get }
    var packages: any PackagePort { get }
    var scripts: any ScriptPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `DragonFlightWorldAdapter`, over its own narrow host.
public struct DragonFlightCandidatesAdapter {
    public let game: any DragonFlightCandidatesHost
}

extension DragonFlightCandidatesAdapter {
    public func candidate(_ actor: CombatActorObservation) -> DragonFlightCandidate {
        var candidate = DragonFlightCandidate(
            key: actor.key, feet: actor.feet, yaw: NPCYawMath.heading(fromYaw: actor.facing)
        )
        if
            let loop = game.combat.loop, let target = loop.targets[actor.key],
            let machine = loop.behaviors[actor.key]
        {
            candidate.fight = DragonFightStage(rawValue: machine.flight.stage.rawValue)
            candidate.target = game.actorWorld.combatActor(key: target)?.feet
            candidate.orbitRadius = machine.settings.flight.orbitDistance
        }
        let scripted = game.scripts.bridge?.scriptedState(of: actor.key)
        candidate.isAllowedToFly = scripted?.flag(ScriptedStateName.allowFlying) ?? true
        candidate.canFlyHere = game.streamer?.interiorScene == nil
        candidate.isRidden = game.mounts.drive?.mount == actor.key
        candidate.isDead = actor.isDead
        candidate.packageFlight = game.packages.flightTarget(of: actor.key).map {
            switch $0 {
            case let .point(point): .point(point)
            case let .perch(furniture): .perch(furniture)
            }
        }
        if
            let holder = game.actorWorld.actorValueHolder(for: actor.key),
            let values = game.actorValues.runtime
        {
            let health = ActorValueIdentity.index(named: "Health")
                .flatMap { values.fraction(at: $0, on: holder) } ?? 1
            candidate.isInjured = health < values.baseline(of: holder).injuredHealthPercent
            // The actor value Dragonrend's `VoiceDragonrendEffectScript` raises.
            let rend = ActorValueIdentity.index(named: "Dragon Rend")
                .flatMap { values.value(at: $0, on: holder) } ?? 0
            candidate.isRended = rend > 0
        }
        return candidate
    }

    /// A flying race that a script allows to fly and the player does not ride.
    public func actorFliesPackages(_ actor: ReferenceKey) -> Bool {
        let scripted = game.scripts.bridge?.scriptedState(of: actor)
        return game.combatWorld.actorFlies(actor)
            && scripted?.flag(ScriptedStateName.allowFlying) ?? true
            && game.mounts.drive?.mount != actor
    }
}
