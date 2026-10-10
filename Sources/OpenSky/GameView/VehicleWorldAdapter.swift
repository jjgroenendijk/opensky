// App side of the vehicle runtime and the actor AI natives: answers their ports
// from the streamer, the world state, the idles, and the packages, and runs the
// vehicle pass in the frame loop. See docs/engine/vehicles.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
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
        renderer.onWorldUpdate = { [weak vehicles] delta in
            advanceWorld?(delta)
            vehicles?.advance()
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

    func vehicleDrawnPose(of key: ReferenceKey)
        -> (formID: UInt32, pose: ReferenceTransformOverride)?
    {
        guard
            let entry = game.streamer?.referenceEntry(key: key),
            let state = game.scripts.bridge?.referenceState(for: key)
        else { return nil }
        return (entry.formID.rawValue, state.transform)
    }

    func publishVehicleDeltas(_ deltas: [UInt32: float4x4]) {
        game.renderer?.vehicleInstanceDeltas = deltas
    }

    func placePlayer(at pose: ReferenceTransformOverride) {
        game.renderer?.placePlayerFeet(at: pose.position)
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
        guard vehicles.attach(vehicle, to: horse) else { return }
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
