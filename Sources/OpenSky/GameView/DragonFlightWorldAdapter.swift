// App side of `DragonFlightCoordinator`: which loaded actors fly and how they fight,
// and the streamer hold, graph inputs, and impacts a flight needs. The rules live in
// `DragonFlightRules` (docs/engine/dragon-flight.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DragonFlightWorldAdapter` reads from the session.
@MainActor
protocol DragonFlightWorldHost: AnyObject {
    var actorGraphs: ActorGraphCoordinator { get }
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var combat: CombatCoordinator { get }
    var combatWorld: CombatWorldAdapter { get }
    var dragonFlight: DragonFlightCoordinator { get }
    var gameSession: GameSession? { get }
    var idleWorld: IdleWorldAdapter { get }
    var mounts: MountCoordinator { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
}

final class DragonFlightWorldAdapter {
    unowned let game: any DragonFlightWorldHost
    /// The wing dust of a landing approach. The game names no set for the engine's
    /// `FlightLandingEffect`; this is the take-off dust `DragonActorScript` plays.
    static let landingDustSet = "FXDragonTakeoffImpactSet"

    init(game: any DragonFlightWorldHost) {
        self.game = game
    }

    func wire(gameSession: GameSession) {
        gameSession.worldTick.register(.dragonFlight) { [weak self] delta in
            self?.game.dragonFlight.tick(deltaTime: delta)
        }
    }

    /// `GetFlyingState` of each actor in the air, the player's dragon included.
    var flyingStates: [ReferenceKey: Int32] {
        var states = game.dragonFlight.flights.mapValues(\.phase.rawValue)
        if let drive = game.mounts.drive, let phase = drive.flight?.phase, phase.isFlying {
            states[drive.mount] = phase.rawValue
        }
        return states
    }

    /// `GetIsFlying`: in the air until its landing is done.
    func isFlying(_ actor: ReferenceKey) -> Bool {
        if let drive = game.mounts.drive, drive.mount == actor {
            return drive.flight?.phase.isFlying == true
        }
        return game.dragonFlight.phase(of: actor).isFlying
    }

    private func candidate(_ actor: CombatActorObservation) -> DragonFlightCandidate {
        var candidate = DragonFlightCandidate(
            key: actor.key, feet: actor.feet, yaw: .pi / 2 - actor.facing
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
        if
            let holder = game.actorWorld.actorValueHolder(for: actor.key),
            let values = game.actorValues.runtime
        {
            let health = values.fraction(at: Self.healthIndex, on: holder) ?? 1
            candidate.isInjured = health < values.baseline(of: holder).injuredHealthPercent
            candidate.isRended = (values.value(at: Self.dragonRendIndex, on: holder) ?? 0) > 0
        }
        return candidate
    }

    static let healthIndex = ActorValueIdentity.index(named: "Health") ?? 24
    /// The actor value Dragonrend's `VoiceDragonrendEffectScript` raises.
    static let dragonRendIndex = ActorValueIdentity.index(named: "Dragon Rend") ?? 155
}

extension DragonFlightWorldAdapter: DragonFlightWorld {
    var dragonFlightSettings: DragonFlightSettings {
        game.worldData?.dragonFlightSettings ?? .standard
    }

    /// The living fliers, and the dead ones still in the air, which crash-land.
    func dragonFlightCandidates() -> [DragonFlightCandidate] {
        let inAir = game.dragonFlight.flights
        return game.actorWorld.combatActors()
            .filter { ($0.isDead ? inAir[$0.key] != nil : true) && $0.key != .player }
            .filter { game.combatWorld.actorFlies($0.key) }
            .map(candidate)
    }

    /// Each enabled perch seat in the loaded cells. A seat heading is clockwise from +Y.
    func dragonPerches() -> [DragonPerch] {
        guard let streamer = game.streamer else { return [] }
        return streamer.residentInteractions.flatMap { interaction -> [DragonPerch] in
            guard let key = streamer.referenceEntry(formID: interaction.reference)?.key
            else { return [] }
            return interaction.seats.filter { $0.isEnabled && $0.rules.isPerch }.map { seat in
                DragonPerch(reference: key, feet: seat.root, yaw: .pi / 2 - seat.heading)
            }
        }
    }

    func landingEvent(for actor: ReferenceKey, perch: ReferenceKey?) -> String? {
        game.idleWorld.idles.actionEvent(
            DragonFlightGraphNames.landingAction, for: actor, target: perch
        )
    }

    func holdForFlight(_ actor: ReferenceKey) -> (feet: SIMD3<Float>, yaw: Float)? {
        game.streamer?.takeRiddenActor(actor).map { ($0.feetPosition, $0.yaw) }
    }

    func moveFlying(
        _ actor: ReferenceKey, state: DragonFlightState,
        inputs: [(name: String, value: BehaviorVariableValue)]
    ) {
        game.streamer?.steerRiddenActor(actor, to: state.feet, yaw: state.yaw)
        for (name, value) in inputs {
            game.actorGraphs.setVariable(value, named: name, on: actor)
        }
        game.actorGraphs.setMotion(ActorGraphMotion(isMoving: state.speed > 0.5), for: actor)
    }

    func releaseFromFlight(_ actor: ReferenceKey) {
        game.streamer?.releaseRiddenActor(actor)
        game.actorGraphs.setMotion(.still, for: actor)
    }

    func flightGroundHeight(at point: SIMD2<Float>) -> Float? {
        game.gameSession?.terrainSampler?(point)?.height
    }

    func raiseFlightEvent(_ name: String, on actor: ReferenceKey) {
        game.actorGraphs.raise(name, on: actor)
    }

    func playLandingDust(_: ReferenceKey, at point: SIMD3<Float>) {
        guard
            let impacts = game.worldData?.footstepStore.map(MeleeImpactResolver.init(footsteps:)),
            let set = impacts.dataSet(editorID: Self.landingDustSet),
            let impact = impacts.resolve(dataSet: set, material: nil)
        else { return }
        game.combatWorld.playImpact(impact, at: point)
    }
}
