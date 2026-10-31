// The shell of the vehicle rules in `VehicleCore`: reads live poses, bones, and
// the ground from the session each frame and returns the followers' live poses.
// The player rider is placed, not drawn. See docs/engine/vehicles.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// What the vehicle coordinator reads from the session.
@MainActor
public protocol VehicleWorld: AnyObject {
    /// Where the reference is now: a walking actor's live pose, else its placed pose.
    func vehiclePose(of key: ReferenceKey) -> ReferenceTransformOverride?
    /// The FormID the reference is drawn under, while a loaded cell draws it.
    func vehicleFormID(of key: ReferenceKey) -> UInt32?
    /// A bone of the reference's live pose, in its root frame; nil while it loads.
    func vehicleBone(of key: ReferenceKey, named bone: String) -> SIMD3<Float>?
    /// The highest ground at or below `point`: terrain, or a road, bridge, or floor.
    /// The references in `vehicles` are not ground.
    func vehicleGround(at point: SIMD3<Float>, excluding vehicles: Set<ReferenceKey>) -> Float?
    /// `VehicleWheels.contacts` of the reference's model: nil while it loads, empty
    /// when it has no wheels or no model.
    func vehicleWheels(of key: ReferenceKey) -> [SIMD2<Float>]?
}

@MainActor
public final class VehicleCoordinator {
    public private(set) var core = VehicleCore()
    public private(set) var lastPoses: [ReferenceKey: ReferenceTransformOverride] = [:]
    /// The horse the player sat on last, kept after they dismount.
    public private(set) var playersLastMount: ReferenceKey?
    weak let world: (any VehicleWorld)?
    private var hasDeltas = false

    public init(world: any VehicleWorld) {
        self.world = world
    }

    /// Puts `rider` in its seat on `vehicle`, as `SetVehicle` does.
    @discardableResult
    public func board(_ rider: ReferenceKey, on vehicle: ReferenceKey) -> Bool {
        lastPoses[rider] = nil
        return core.board(rider, on: vehicle)
    }

    /// `SetVehicle`: `None`, or the rider itself, takes the rider off its vehicle.
    public func setVehicle(_ rider: ReferenceKey, vehicle: ReferenceKey?) -> [VehicleCommand] {
        guard let vehicle, vehicle != rider else { return detach(rider) }
        board(rider, on: vehicle)
        return []
    }

    /// The cart exit state's `ExitCartEnd` takes the rider off its vehicle.
    public func animationEvent(_ name: String, from actor: ReferenceKey) -> [VehicleCommand] {
        guard name.caseInsensitiveCompare(VehicleCore.exitEvent) == .orderedSame else { return [] }
        return detach(actor)
    }

    /// Seats `rider` on the horse's saddle bone, facing the way the horse faces.
    @discardableResult
    public func seat(_ rider: ReferenceKey, on horse: ReferenceKey, bone: String) -> Bool {
        lastPoses[rider] = nil
        guard core.seat(rider, on: horse, bone: bone) else { return false }
        if rider == .player {
            playersLastMount = horse
        }
        return true
    }

    /// `TetherToHorse`: the cart trails the horse at the distance it has now.
    @discardableResult
    public func tow(_ cart: ReferenceKey, by horse: ReferenceKey) -> Bool {
        guard
            let world,
            let cartPose = currentPose(of: cart),
            let horsePose = currentPose(of: horse)
        else { return false }
        let linked = linkedReferences.union([cart, horse])
        return core.tow(
            cart, by: horse, followerPose: cartPose, carrierPose: horsePose,
            ground: { world.vehicleGround(at: $0, excluding: linked) }
        )
    }

    public func detach(_ follower: ReferenceKey) -> [VehicleCommand] {
        guard core.links[follower] != nil else { return [] }
        let commands = lastPoses[follower].map { [VehicleCommand.followerRests(follower, at: $0)] }
        core.detach(follower)
        lastPoses[follower] = nil
        return commands ?? []
    }

    /// Every follower and carrier, read before `core` changes so the ground port
    /// does not read `core` while it is being written.
    private var linkedReferences: Set<ReferenceKey> {
        Set(core.links.flatMap { [$0.key, $0.value.carrier] })
    }

    public func advance() -> [VehicleCommand] {
        guard let world else { return [] }
        guard !core.links.isEmpty else {
            guard hasDeltas else { return [] }
            hasDeltas = false
            return [.publishVehiclePoses([:]), .publishCarriedPoses([:]), .publishLinks([])]
        }
        loadWheels(world: world)
        let linked = linkedReferences
        lastPoses = core.advance(
            base: { world.vehiclePose(of: $0) },
            bone: { world.vehicleBone(of: $0, named: $1) },
            ground: { world.vehicleGround(at: $0, excluding: linked) }
        )
        var commands: [VehicleCommand] = []
        var placements: [UInt32: float4x4] = [:]
        for (key, pose) in lastPoses {
            if key == .player {
                commands.append(.placePlayer(pose))
            } else if let formID = world.vehicleFormID(of: key) {
                commands.append(.followerMoved(key, to: pose))
                placements[formID] = VehicleCore.matrix(pose)
            }
        }
        for (key, link) in core.links {
            if case let .towed(tow) = link.seat {
                commands.append(.spinWheels(key, rolled: tow.rolled))
            }
        }
        commands += [
            .publishVehiclePoses(placements),
            .publishCarriedPoses(lastPoses.filter { $0.key != .player }),
            .publishLinks(linked)
        ]
        hasDeltas = true
        return commands
    }

    /// A towed cart rests on its wheels once its model has loaded.
    private func loadWheels(world: any VehicleWorld) {
        for (key, link) in core.links {
            guard
                case let .towed(tow) = link.seat, tow.wheels == nil,
                let wheels = world.vehicleWheels(of: key)
            else { continue }
            core.setWheels(wheels, for: key)
        }
    }

    private func currentPose(of key: ReferenceKey) -> ReferenceTransformOverride? {
        lastPoses[key] ?? world?.vehiclePose(of: key)
    }
}
