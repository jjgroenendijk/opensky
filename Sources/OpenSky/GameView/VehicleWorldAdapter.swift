// App side of the vehicle runtime and the actor AI natives: answers their ports
// from the streamer, the world state, the idles, and the packages, and runs the
// vehicle pass in the frame loop. See docs/engine/vehicles.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

final class VehicleWorldAdapter {
    unowned let game: GameViewController
    let vehicles = VehicleCoordinator()
    /// True after `SetPlayerAIDriven(true)`: the player's packages move the player.
    private(set) var isPlayerAIDriven = false
    /// The cell each follower is moving into while its old cell still draws it.
    private var crossings: [ReferenceKey: CellCoordinate] = [:]
    /// The start of the seat idle the player's view was last turned for.
    private var facedIdleStart: Float?

    init(game: GameViewController) {
        self.game = game
        vehicles.attach(world: self)
    }

    /// After the idles and packages, so a follower reads where its carrier ended up.
    func wireVehicles(renderer: Renderer) {
        game.scripts.bridge?.actorAI = self
        let scripts = game.scripts
        game.idleWorld.idles.onAnimationEvent = { [weak scripts, weak vehicles] actor, name in
            if name == VehicleCore.exitEvent {
                vehicles?.detach(actor)
            }
            scripts?.runtime?.queueAnimationEvent(sender: actor, name: name)
        }
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak vehicles, weak renderer] delta in
            advanceWorld?(delta)
            vehicles?.advance()
            if vehicles?.lastPoses[.player] == nil {
                renderer?.playerSeat = nil
            }
        }
    }
}

extension VehicleWorldAdapter: VehicleWorld {
    func vehiclePose(of key: ReferenceKey) -> ReferenceTransformOverride? {
        if key == .player {
            return game.renderer
                .map { ReferenceTransformOverride(position: $0.walkController.feetPosition) }
        }
        return game.streamer?.npcTransform(for: key)
            ?? game.scripts.bridge?.placement(of: key)?.state.transform
    }

    func vehicleFormID(of key: ReferenceKey) -> UInt32? {
        game.streamer?.referenceEntry(key: key)?.formID.rawValue
    }

    func publishVehiclePoses(_ poses: [UInt32: float4x4]) {
        game.renderer?.vehicleInstancePoses = poses
    }

    func publishCarriedPoses(_ poses: [ReferenceKey: ReferenceTransformOverride]) {
        game.streamer?.npcMovementState.carried = poses
    }

    /// The player's root sits on the vehicle, as every rider's does. While the player
    /// plays a seat idle, the eye goes to the clip's head bone, so the view sits in the seat.
    func placePlayer(at pose: ReferenceTransformOverride) {
        guard let renderer = game.renderer else { return }
        guard
            let head = game.idleWorld.idles.idleBone(
                of: .player, named: DialogueCamera.headBoneName
            )
        else {
            renderer.playerSeat = nil
            renderer.placePlayerFeet(at: pose.position)
            return
        }
        let root = MatrixMath.placement(position: pose.position, rotation: pose.rotation, scale: 1)
        renderer.playerSeat = root
        let eye = root * SIMD4(head, 1)
        let height = renderer.walkController.capsule.eyeHeight
        renderer.placePlayerFeet(at: SIMD3(eye.x, eye.y, eye.z - height))
        faceSeat(root: root, renderer: renderer)
    }

    /// A new seat idle turns the view the way the seat's head faces, once; the player
    /// may look around after.
    private func faceSeat(root: float4x4, renderer: Renderer) {
        let idles = game.idleWorld.idles
        guard
            let start = idles.idleStart(of: .player), start != facedIdleStart,
            let forward = idles.idleBoneForward(of: .player, named: DialogueCamera.headBoneName)
        else { return }
        facedIdleStart = start
        let world = root * SIMD4(forward, 0)
        guard abs(world.x) + abs(world.y) > 0.001 else { return }
        renderer.freeFlyCamera.yaw = atan2(world.y, world.x)
    }

    /// A follower drawn by a cell it left moves into the cell it is now in, so it does
    /// not vanish when the old cell unloads. The old cell drops it.
    func vehicleFollowerMoved(_ key: ReferenceKey, to pose: ReferenceTransformOverride) {
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

    func vehicleGround(at point: SIMD2<Float>) -> Float? {
        game.streamer?.sampleTerrain(at: point)?.height
    }

    func vehicleFollowerRests(_ key: ReferenceKey, at pose: ReferenceTransformOverride) {
        guard key != .player else { return }
        let cell = game.streamer?.cellLocation(of: key)
        game.worldState.set(pose, for: key, in: cell)
        game.worldState.reset(.vehicleLink, for: key)
    }
}

extension VehicleWorldAdapter: PapyrusActorAIBridge {
    func evaluatePackage(_ actor: ReferenceKey) {
        game.packages.evaluate(actor)
    }

    func setVehicle(_ rider: ReferenceKey, vehicle: ReferenceKey?) {
        guard let vehicle else {
            vehicles.detach(rider)
            return
        }
        vehicles.board(rider, on: vehicle)
    }

    func tether(_ vehicle: ReferenceKey, to horse: ReferenceKey) {
        guard vehicles.tow(vehicle, by: horse) else { return }
        let cell = game.streamer?.cellLocation(of: vehicle)
        game.worldState.set(ReferenceVehicleLink(carrier: horse), for: vehicle, in: cell)
    }

    func playIdle(_ idle: ResolvedFormID, on actor: ReferenceKey) -> Bool {
        game.idleWorld.idles.fireIdle(idle, on: actor, ignoringConditions: true)?.chosen != nil
    }

    func setPlayerAIDriven(_ driven: Bool) {
        isPlayerAIDriven = driven
        if !driven {
            game.renderer?.playerWalkPath = []
        }
    }
}
