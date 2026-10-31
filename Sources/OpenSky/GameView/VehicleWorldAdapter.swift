// App side of the vehicle runtime and the actor AI natives: answers their ports
// from the streamer, the world state, the idles, and the packages, and runs the
// vehicle pass in the frame loop. See docs/engine/vehicles.md.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyTerrain
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `VehicleWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol VehicleWorldHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback?
    var idleWorld: IdleWorldAdapter { get }
    var packages: PackageCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
    var vehicles: VehicleCoordinator { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

final class VehicleWorldAdapter {
    unowned let game: any VehicleWorldHost
    var vehicles: VehicleCoordinator {
        game.vehicles
    }

    /// True after `SetPlayerAIDriven(true)`: the player's packages move the player.
    private(set) var isPlayerAIDriven = false
    /// The cell each follower is moving into while its old cell still draws it.
    private var crossings: [ReferenceKey: CellCoordinate] = [:]
    /// The vehicle seated the player on the last step.
    private var ridesPlayer = false
    /// The start of the seat idle the player's view was last turned for.
    private var facedIdleStart: Float?
    /// Wheel contacts by model path, read off the main actor.
    private var wheels: AssetLoader<String, [SIMD2<Float>]>?

    init(game: any VehicleWorldHost) {
        self.game = game
    }

    /// After the idles and packages, so a follower reads where its carrier ended up.
    func wireVehicles(gameSession: GameSession) {
        wireWheels(gameSession: gameSession)
        gameSession.worldTick.register(.vehicles) { [weak self, weak gameSession] _ in
            guard let self else { return }
            run(vehicles.advance())
            // Only the end of a ride frees the seat; a chair holds the player too.
            let rides = vehicles.lastPoses[.player] != nil
            if ridesPlayer, !rides {
                gameSession?.playerSeat = nil
            }
            ridesPlayer = rides
        }
    }

    /// Each clip annotation an idle passes.
    func handleIdleAnimationEvent(_ name: String, from actor: ReferenceKey) {
        // The player's idles run on its graph, whose events arrive through the bridge.
        if actor != .player {
            game.gameSession?.animationEvents?.handle(name, from: actor)
        }
        run(vehicles.animationEvent(name, from: actor))
        if name.caseInsensitiveCompare(IdleCore.killEvent) == .orderedSame {
            game.scripts.bridge?.killActor(actor, killer: nil)
        }
        game.scripts.runtime?.queueAnimationEvent(sender: actor, name: name)
    }

    private func wireWheels(gameSession: GameSession) {
        guard let files = game.worldData?.scriptFileSystem else {
            return
        }
        let wheels = AssetLoader<String, [SIMD2<Float>]> { path in
            try VehicleWheels.contacts(in: NIFFile(data: files.contents(forPath: path)))
        }
        self.wheels = wheels
        gameSession.assetDrains.register(.vehicleWheels) { _ in wheels.drain() }
    }
}

extension VehicleWorldAdapter: VehicleWorld {
    func vehiclePose(of key: ReferenceKey) -> ReferenceTransformOverride? {
        if key == .player {
            return game.gameSession
                .map { ReferenceTransformOverride(position: $0.walkController.feetPosition) }
        }
        return game.streamer?.npcTransform(for: key)
            ?? game.scripts.bridge?.placement(of: key)?.state.transform
    }

    func vehicleFormID(of key: ReferenceKey) -> UInt32? {
        game.streamer?.referenceEntry(key: key)?.formID.rawValue
    }

    func run(_ commands: [VehicleCommand]) {
        for command in commands {
            switch command {
            case let .publishVehiclePoses(poses): game.gameSession?.instancePoses
                .vehiclePoses = poses
            case let .publishCarriedPoses(poses): game.streamer?.npcMovementState.carried = poses
            case let .publishLinks(linked):
                game.streamer?.npcMovementState.vehicleLinkedActors = linked
            case let .placePlayer(pose): placePlayer(at: pose)
            case let .followerMoved(key, pose): vehicleFollowerMoved(key, to: pose)
            case let .followerRests(key, pose): vehicleFollowerRests(key, at: pose)
            case let .spinWheels(key, distance): spinVehicleWheels(of: key, rolled: distance)
            }
        }
    }

    func detach(_ follower: ReferenceKey) {
        run(vehicles.detach(follower))
    }

    /// The player's root sits on the vehicle, as every rider's does. While the player
    /// plays a seat idle, the eye goes to the clip's head bone, so the view sits in the seat.
    func placePlayer(at pose: ReferenceTransformOverride) {
        guard let gameSession = game.gameSession else { return }
        let head = game.idleWorld.idles.idleBone(of: .player, named: DialogueCamera.headBoneName)
        let root = MatrixMath.placement(position: pose.position, rotation: pose.rotation, scale: 1)
        gameSession.seatPlayer(at: root, head: head)
        if head != nil {
            faceSeat(root: root, gameSession: gameSession)
        }
    }

    /// A new seat idle turns the view the way the seat's head faces, once; the player
    /// may look around after.
    private func faceSeat(root: float4x4, gameSession: GameSession) {
        let idles = game.idleWorld.idles
        guard
            let start = idles.idleStart(of: .player), start != facedIdleStart,
            let forward = idles.idleBoneForward(of: .player, named: DialogueCamera.headBoneName)
        else { return }
        facedIdleStart = start
        let world = root * SIMD4(forward, 0)
        guard abs(world.x) + abs(world.y) > 0.001 else { return }
        gameSession.freeFlyCamera.yaw = atan2(world.y, world.x)
    }

    /// A follower drawn by a cell it left moves into the cell it is now in, so it does
    /// not vanish when the old cell unloads. The old cell drops it.
    func vehicleFollowerMoved(_ key: ReferenceKey, to pose: ReferenceTransformOverride) {
        if let formID = game.streamer?.referenceEntry(key: key)?.formID {
            game.streamer?.npcMovementState.vehiclePoses[formID] = VehicleCore.matrix(pose)
        }
        guard
            let streamer = game.streamer,
            case let .exterior(drawing)? = streamer.cellLocation(of: key)
        else { return }
        let now = CellGridManager.cellCoordinate(for: pose.position)
        guard now != drawing, streamer.composition.cells[now] != nil else {
            crossings[key] = nil
            return
        }
        // Until the rebuild lands, the old cell still draws it: write once per crossing.
        guard crossings[key] != now else { return }
        crossings[key] = now
        game.worldState.set(pose, for: key, in: .exterior(now))
        game.scripts.bridge?.relocate(key, to: .exterior(now))
        streamer.requestRebuild(of: .exterior(drawing))
    }

    func vehicleBone(of key: ReferenceKey, named bone: String) -> SIMD3<Float>? {
        guard
            let renderer = game.renderer,
            let pose = game.actorPlayback(for: key)?.skeletonPose(at: renderer.animationTime),
            let index = pose.bones.index(of: bone),
            pose.matrices.indices.contains(index)
        else { return nil }
        let origin = pose.matrices[index].columns.3
        return SIMD3(origin.x, origin.y, origin.z)
    }

    func vehicleHasBone(_ key: ReferenceKey, named bone: String) -> Bool {
        game.actorPlayback(for: key)?.hasBone(named: bone) ?? false
    }

    func vehicleGround(at point: SIMD3<Float>, excluding vehicles: Set<ReferenceKey>) -> Float? {
        guard let streamer = game.streamer else { return nil }
        let terrain = streamer.sampleTerrain(at: SIMD2(point.x, point.y))?.height
        let depth = point.z - (terrain ?? point.z - Self.groundSearchDepth) + 1
        guard depth > 0 else { return terrain }
        let query = ShapeSweepQuery.sphere(
            center: point, radius: 1, direction: SIMD3(0, 0, -1), maximumDistance: depth
        )
        // A cart's own collision stays where it was placed, so it is not ground.
        let linked = Set(vehicles.compactMap { streamer.referenceEntry(key: $0)?.formID })
        let shapes = streamer.staticCollisionCandidates(overlapping: query.bounds)
            .filter { !linked.contains($0.reference) }
        let floor = ShapeSweeper.firstHit(query: query, shapes: shapes).map(\.position.z)
        return [terrain, floor].compactMap(\.self).max()
    }

    /// How far below the search point a floor counts where no terrain answers.
    private static let groundSearchDepth: Float = 4096

    func vehicleWheels(of key: ReferenceKey) -> [SIMD2<Float>]? {
        guard
            let wheels,
            let path = game.streamer?.placedRecords?.baseModelPath(for: key)
        else { return [] }
        switch wheels.state(of: path) {
        case .loading: return nil
        case let .ready(contacts): return contacts
        case .failed: return []
        }
    }

    func spinVehicleWheels(of key: ReferenceKey, rolled distance: Float) {
        guard
            let streamer = game.streamer,
            let formID = vehicleFormID(of: key),
            let vehicle = streamer.residentAnimatedVehicles().first(where: {
                $0.reference == formID
            })
        else { return }
        vehicle.pose.publish(vehicle.rig.pose(rolled: distance))
    }

    func vehicleFollowerRests(_ key: ReferenceKey, at pose: ReferenceTransformOverride) {
        guard key != .player else { return }
        let cell = game.streamer?.cellLocation(of: key)
        game.worldState.set(pose, for: key, in: cell)
        game.worldState.reset(.vehicleLink, for: key)
        game.streamer?.restActor(key, at: pose)
    }
}

extension VehicleWorldAdapter: PapyrusActorAIBridge {
    func evaluatePackage(_ actor: ReferenceKey) {
        game.packages.evaluate(actor)
    }

    func setVehicle(_ rider: ReferenceKey, vehicle: ReferenceKey?) {
        run(vehicles.setVehicle(rider, vehicle: vehicle))
    }

    func tether(_ vehicle: ReferenceKey, to horse: ReferenceKey) {
        guard vehicles.tow(vehicle, by: horse) else { return }
        let cell = game.streamer?.cellLocation(of: vehicle)
        game.worldState.set(ReferenceVehicleLink(carrier: horse), for: vehicle, in: cell)
    }

    func playIdle(_ idle: ResolvedFormID, on actor: ReferenceKey) -> Bool {
        game.idleWorld.idles.fireIdle(idle, on: actor, ignoringConditions: true)?.chosen != nil
    }

    func linkDependentAnimation(_ dependent: ReferenceKey, to owner: ReferenceKey, linked: Bool) {
        if linked {
            game.idleWorld.idles.addDependent(dependent, of: owner)
        } else {
            game.idleWorld.idles.removeDependent(dependent, of: owner)
        }
    }

    func setPlayerAIDriven(_ driven: Bool) {
        isPlayerAIDriven = driven
        if !driven {
            game.gameSession?.playerWalkPath = []
        }
    }
}
