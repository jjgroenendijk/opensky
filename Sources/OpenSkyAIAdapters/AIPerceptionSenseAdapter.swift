import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyMagic
import OpenSkyNavigation
public import OpenSkyPerception
public import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AIPerceptionSenseAdapter` reads from the session.
@MainActor
public protocol AIPerceptionSenseHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var crime: any CrimePort { get }
    var crimeWorld: any CrimeWorldPort { get }
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var packages: any PackagePort { get }
    var perception: any PerceptionPort { get }
    var progression: any ProgressionPort { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `AIWorldAdapter`, over its own narrow host.
public struct AIPerceptionSenseAdapter {
    public unowned let owner: AIWorldAdapter
    public unowned let game: any AIPerceptionSenseHost
}

extension AIPerceptionSenseAdapter {
    public func perceptionCandidates() -> [PerceptionCandidate] {
        let readouts = game.packages.readouts().filter { $0.currentPackage != nil }
        let packaged = Set(readouts.map(\.actor))
        let sleepers = Set(readouts.filter { $0.procedure == .sleep }.map(\.actor))
        let isExterior = game.streamer?.interiorScene == nil
        return game.actorWorld.combatActors().map { actor in
            var observer = PerceptionObserver(
                key: actor.key,
                feet: actor.feet,
                eye: actor.feet + SIMD3(0, 0, actor.capsule.eyeHeight * max(actor.scale, 0)),
                facing: actor.facing,
                isExterior: isExterior,
                label: actor.label,
                sneakSkill: owner.detectionSense.sneakSkill(of: actor.key)
            )
            observer.isSleeping = sleepers.contains(actor.key)
            observer.isFlying = game.dragonFlightWorld.isFlying(actor.key)
            observer.blindness = owner.detectionSense.blindness(of: actor.key)
            observer.combatTarget = game.combat.loop?.combatTarget(of: actor.key)
            return PerceptionCandidate(
                observer: observer,
                isDead: actor.isDead,
                isHostile: game.factions.hostility(of: actor.key) == .hostile,
                isEngaged: game.combat.loop?.phase(of: actor.key)?.isEngaged == true,
                hasPackage: packaged.contains(actor.key)
            )
        }
    }

    public func perceptionTargets() -> [PerceptionTarget] {
        guard let gameSession = game.gameSession else { return [] }
        let status = gameSession.locomotion.status
        let isMoving = simd_length_squared(status.lastPlan.horizontalDisplacement) > 0
        return [PerceptionTarget(
            key: .player,
            feet: status.feetPosition,
            eye: status.feetPosition + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight),
            gait: isMoving ? status.gait : nil,
            isSneaking: status.gait == .sneak,
            traits: owner.detectionSense.playerDetectionTraits(
                at: status.feetPosition, eyeHeight: PlayerCapsule.standard.eyeHeight
            ),
            name: "Player"
        )]
    }

    public func perceptionHasLineOfSight(
        from origin: SIMD3<Float>,
        to destination: SIMD3<Float>
    ) -> Bool {
        guard let streamer = game.streamer else { return true }
        let offset = destination - origin
        let distance = simd_length(offset)
        guard
            distance.isFinite, distance > 0,
            let ray = InteractionRay(origin: origin, direction: offset, maximumDistance: distance)
        else { return true }
        return !streamer.staticCollisionBlocks(ray: ray)
    }

    public func run(_ commands: [PerceptionCommand]) {
        for case let .reportSneakSkillUse(amount, actor) in commands {
            _ = game.progression.reportSkillUse(
                SkillUseEvent(actor: actor, action: .hidden, amount: amount)
            )
        }
    }
}
