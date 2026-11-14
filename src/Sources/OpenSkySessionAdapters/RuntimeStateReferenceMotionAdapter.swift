import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
public import OpenSkyWorldConditionFunctions
import OpenSkyWorldConditions
import OpenSkyWorldInterface
public import OpenSkyWorldState

/// What `RuntimeStateReferenceMotionAdapter` reads from the session.
@MainActor
public protocol RuntimeStateReferenceMotionHost: AnyObject, SendableMetatype {
    var dragonFlight: any DragonFlightPort { get }
    var dragonFlightWorld: any DragonFlightWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var mountWorld: any MountWorldPort { get }
    var streamer: any CellStreamerPort { get }
    var vehicleWorld: any VehicleWorldPort { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `RuntimeStateWorldAdapter`, over its own narrow host.
public struct RuntimeStateReferenceMotionAdapter {
    public let game: any RuntimeStateReferenceMotionHost
    let state: RuntimeStatePartState
}

extension RuntimeStateReferenceMotionAdapter {
    public func addMountSeams(to context: inout ConditionContext) {
        ReferenceConditionReads(game: game).addMountSeams(to: &context)
    }

    /// Lock, open, and deletion state of every reference a run-on can name.
    public func referenceFacts(of references: RuntimeReferenceIndex)
        -> ReferenceConditionResolution
    {
        ReferenceConditionReads(game: game).referenceFacts(of: references)
    }

    /// Moving actors and the player up front; any other reference only when a condition
    /// reads it, so a context build walks no references.
    public func motionResolution(references: RuntimeReferenceIndex) -> MotionConditionResolution {
        var facts = game.streamer.npcMovement.motionFacts()
        if let gameSession = game.gameSession {
            let status = gameSession.locomotion.status
            facts[.player] = ReferenceMotionFacts(
                position: gameSession.walkController.feetPosition,
                rotation: SIMD3(0, 0, NPCYawMath.heading(fromYaw: status.yaw)),
                velocity: SIMD3(
                    status.horizontalVelocity.x, status.horizontalVelocity.y,
                    status.verticalVelocity
                )
            )
        }
        let streamer = game.streamer
        let worldState = game.worldState
        return MotionConditionResolution(facts: facts) { [weak streamer, weak worldState] key in
            guard let streamer, let worldState, let entry = references[key] else { return nil }
            let state = worldState.resolvedState(for: entry)
            let moved = streamer.npcTransform(for: key)
            return ReferenceMotionFacts(
                position: moved?.position ?? state.transform.position,
                rotation: moved?.rotation ?? state.transform.rotation
            )
        }
    }

    public func placeResolution(references: RuntimeReferenceIndex) -> PlaceConditionResolution {
        let deaths = deathView()
        return PlaceConditionResolution(
            deadReferences: deaths.dead,
            deadCounts: deaths.counts,
            playerRegions: Set(game.streamer.playerRegions),
            visibleMarkers: visibleMarkers(in: references)
        )
    }

    private func deathView() -> DeathView {
        let worldState = game.worldState
        let key = DeathViewKey(
            store: ObjectIdentifier(worldState),
            streamer: ObjectIdentifier(game.streamer),
            cells: game.streamer.residentCellLocations,
            deaths: worldState.revision(of: [.death])
        )
        return state.conditionCaches.deaths.value(for: key) {
            var view = DeathView()
            for key in worldState.sortedDirtyKeys() {
                guard worldState.component(ActorDeathState.self, for: key)?.isDead == true else {
                    continue
                }
                view.dead.insert(key)
                let entry = game.streamer.referenceEntry(key: key)
                    ?? game.streamer.pluginPlacement(of: key)?.entry
                if let base = entry?.placedActor?.base {
                    view.counts[base, default: 0] += 1
                }
            }
            return view
        }
    }

    private func visibleMarkers(in references: RuntimeReferenceIndex) -> Set<ReferenceKey> {
        let worldState = game.worldState
        let key = MarkerViewKey(
            store: ObjectIdentifier(worldState),
            markers: worldState.revision(of: [.mapMarker]),
            references: references.mapMarkerKeys
        )
        return state.conditionCaches.markers.value(for: key) {
            var markers: Set<ReferenceKey> = []
            for key in references.mapMarkerKeys {
                guard let entry = references[key], let record = entry.placedReference?.mapMarker
                else { continue }
                let state = worldState.component(MapMarkerState.self, for: entry.key)
                    ?? MapMarkerState(record: record)
                if state.isVisible {
                    markers.insert(entry.key)
                }
            }
            return markers
        }
    }
}

/// The mount and reference facts a condition run-on reads.
struct ReferenceConditionReads {
    let game: any RuntimeStateReferenceMotionHost

    func addMountSeams(to context: inout ConditionContext) {
        let vehicles = game.vehicleWorld.vehicles
        context.mounts = MountConditionResolution(
            mounts: vehicles.core.mounts, playersLastMount: vehicles.playersLastMount,
            flyingMounts: game.mountWorld.flyingMounts
        )
        context.mounts.flyingStates = game.dragonFlightWorld.flyingStates
        context.mounts.canFlyHere = game.streamer.interiorScene == nil
        let requests = game.dragonFlight.landingRequests
        context.mounts.crashLandRequests = Set(requests.filter { $0.value == .crash }.keys)
        context.mounts.hastyLandRequests = Set(requests.filter { $0.value == .hasty }.keys)
    }

    /// Lock, open, and deletion state of any reference a run-on can name, read when a
    /// condition asks for it.
    func referenceFacts(of references: RuntimeReferenceIndex)
        -> ReferenceConditionResolution
    {
        let streamer = game.streamer
        let worldState = game.worldState
        return ReferenceConditionResolution { [weak streamer, weak worldState] key in
            guard let streamer, let worldState, let entry = references[key] else { return nil }
            let state = worldState.resolvedState(for: entry)
            let action = streamer.residentInteraction(reference: entry.formID)?.action
            return ReferenceConditionFacts(
                lock: ReferenceLockState.resolve(
                    baseline: entry.placedReference?.lock,
                    delta: worldState.component(ReferenceLockState.self, for: key)
                ),
                isOpen: state.activation.isOpen,
                isDoor: action == .open,
                isDeleted: state.deletion.isDeleted,
                canOpen: action == .open || action == .search
            )
        }
    }
}
