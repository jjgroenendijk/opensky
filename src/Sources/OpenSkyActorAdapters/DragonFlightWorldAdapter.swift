// App side of `DragonFlightCoordinator`: which loaded actors fly and how they fight,
// and the streamer hold, graph inputs, and impacts a flight needs. The rules live in
// `DragonFlightRules` (docs/engine/dragon-flight.md).

public import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAIPackages
public import OpenSkyBehavior
public import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DragonFlightWorldAdapter` reads from the session.
@MainActor
public protocol DragonFlightWorldHost: AnyObject {
    var actorGraphs: any ActorGraphPort { get }
    var actorWorld: any ActorWorldPort { get }
    var combatWorld: any CombatWorldPort { get }
    var dragonFlight: any DragonFlightPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var mounts: any MountPort { get }
    var packages: any PackagePort { get }
    var streamer: any CellStreamerPort { get }
    var worldData: WorldDataStores? { get }
}

public final class DragonFlightWorldAdapter {
    public let game: any DragonFlightWorldHost
    /// The wing dust of a landing approach. The game names no set for the engine's
    /// `FlightLandingEffect`; this is the take-off dust `DragonActorScript` plays.
    public static let landingDustSet = "FXDragonTakeoffImpactSet"

    public let candidatesHost: any DragonFlightCandidatesHost

    public var candidates: DragonFlightCandidatesAdapter {
        DragonFlightCandidatesAdapter(game: candidatesHost
        )
    }

    public init(game: some DragonFlightWorldHost & DragonFlightCandidatesHost) {
        candidatesHost = game
        self.game = game
    }

    /// `GetFlyingState` of each actor in the air, the player's dragon included.
    public var flyingStates: [ReferenceKey: Int32] {
        var states = game.dragonFlight.flights.mapValues(\.phase.rawValue)
        if let drive = game.mounts.drive, let phase = drive.flight?.phase, phase.isFlying {
            states[drive.mount] = phase.rawValue
        }
        return states
    }

    /// `GetIsFlying`: in the air until its landing is done.
    public func isFlying(_ actor: ReferenceKey) -> Bool {
        if let drive = game.mounts.drive, drive.mount == actor {
            return drive.flight?.phase.isFlying == true
        }
        return game.dragonFlight.phase(of: actor).isFlying
    }
}

extension DragonFlightWorldAdapter: DragonFlightWorld {
    public var dragonFlightSettings: DragonFlightSettings {
        game.worldData?.dragonFlightSettings ?? .standard
    }

    /// The living fliers, and the dead ones still in the air, which crash-land.
    public func dragonFlightCandidates() -> [DragonFlightCandidate] {
        let inAir = game.dragonFlight.flights
        return game.actorWorld.combatActors()
            .filter { ($0.isDead ? inAir[$0.key] != nil : true) && $0.key != .player }
            .filter { game.combatWorld.actorFlies($0.key) }
            .map(candidates.candidate)
    }

    /// Each enabled perch seat in the loaded cells. A seat heading is clockwise from +Y.
    public func dragonPerches() -> [DragonPerch] {
        let streamer = game.streamer
        return streamer.residentInteractions.flatMap { interaction -> [DragonPerch] in
            let seats = interaction.seats.filter { $0.isEnabled && $0.rules.isPerch }
            guard
                !seats.isEmpty,
                let key = streamer.referenceEntry(formID: interaction.reference)?.key
            else { return [] }
            return seats.map { seat in
                DragonPerch(
                    reference: key,
                    feet: seat.root,
                    yaw: NPCYawMath.yaw(fromHeading: seat.heading)
                )
            }
        }
    }

    public func landingEvent(for actor: ReferenceKey, perch: ReferenceKey?) -> String? {
        game.idleWorld.idles.actionEvent(
            DragonFlightGraphNames.landingAction, for: actor, target: perch
        )
    }

    public func holdForFlight(_ actor: ReferenceKey) -> (feet: SIMD3<Float>, yaw: Float)? {
        game.streamer.takeRiddenActor(actor).map { ($0.feetPosition, $0.yaw) }
    }

    public func moveFlying(
        _ actor: ReferenceKey, state: DragonFlightState,
        inputs: [(name: String, value: BehaviorVariableValue)]
    ) {
        game.streamer.steerRiddenActor(actor, to: state.feet, yaw: state.yaw)
        for (name, value) in inputs {
            game.actorGraphs.setVariable(value, named: name, on: actor)
        }
        game.actorGraphs.setMotion(
            ActorGraphMotion(isMoving: state.speed > ActorGraphMotion.movingSpeed),
            for: actor
        )
    }

    public func flightReachedPackageTarget(_ actor: ReferenceKey) {
        game.packages.flightArrived(actor)
    }

    public func releaseFromFlight(_ actor: ReferenceKey) {
        game.streamer.releaseRiddenActor(actor)
        game.actorGraphs.setMotion(.still, for: actor)
    }

    public func flightGroundHeight(at point: SIMD2<Float>) -> Float? {
        game.gameSession?.terrainSampler?(point)?.height
    }

    public func raiseFlightEvent(_ name: String, on actor: ReferenceKey) {
        game.actorGraphs.raise(name, on: actor)
    }

    public func playLandingDust(_: ReferenceKey, at point: SIMD3<Float>) {
        guard let impact = game.combatWorld.impact(
            dataSetEditorID: Self.landingDustSet,
            material: nil
        )
        else { return }
        game.combatWorld.playImpact(impact, at: point)
    }
}

extension DragonFlightWorldAdapter: DragonFlightWorldPort {}
