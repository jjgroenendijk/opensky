// The shell of the vehicle rules in `VehicleCore`: reads live poses, bones, and
// the ground from the session each frame and publishes the followers' live poses.
// The player rider is placed, not drawn. See docs/engine/vehicles.md.

import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// What the vehicle coordinator reads from and writes to the session.
@MainActor
public protocol VehicleWorld: AnyObject {
    /// Where the reference is now: a walking actor's live pose, else its placed pose.
    func vehiclePose(of key: ReferenceKey) -> ReferenceTransformOverride?
    /// The FormID the reference is drawn under, while a loaded cell draws it.
    func vehicleFormID(of key: ReferenceKey) -> UInt32?
    /// Placements by FormID; the renderer turns them into deltas against its build.
    func publishVehiclePoses(_ poses: [UInt32: float4x4])
    /// Every follower but the player, so other systems read where it rides.
    func publishCarriedPoses(_ poses: [ReferenceKey: ReferenceTransformOverride])
    func placePlayer(at pose: ReferenceTransformOverride)
    /// A follower left its carrier and now rests at `pose`.
    func vehicleFollowerRests(_ key: ReferenceKey, at pose: ReferenceTransformOverride)
    /// A follower that is not the player is at `pose` this frame.
    func vehicleFollowerMoved(_ key: ReferenceKey, to pose: ReferenceTransformOverride)
    /// A bone of the reference's live pose, in its root frame; nil while it loads.
    func vehicleBone(of key: ReferenceKey, named bone: String) -> SIMD3<Float>?
    /// The highest ground at or below `point`: terrain, or a road, bridge, or floor.
    /// The references in `vehicles` are not ground.
    func vehicleGround(at point: SIMD3<Float>, excluding vehicles: Set<ReferenceKey>) -> Float?
    /// `VehicleWheels.contacts` of the reference's model: nil while it loads, empty
    /// when it has no wheels or no model.
    func vehicleWheels(of key: ReferenceKey) -> [SIMD2<Float>]?
    /// Turns the follower's wheels for `distance` rolled since the link.
    func spinVehicleWheels(of key: ReferenceKey, rolled distance: Float)
}

@MainActor
public final class VehicleCoordinator {
    public private(set) var core = VehicleCore()
    public private(set) var lastPoses: [ReferenceKey: ReferenceTransformOverride] = [:]
    weak var world: (any VehicleWorld)?
    private var hasDeltas = false

    public init() {}

    public func attach(world: any VehicleWorld) {
        self.world = world
    }

    /// False when either pose is unknown or the link would make a loop.
    @discardableResult
    public func attach(_ follower: ReferenceKey, to carrier: ReferenceKey) -> Bool {
        guard
            let followerPose = currentPose(of: follower),
            let carrierPose = currentPose(of: carrier)
        else { return false }
        return core.attach(
            follower, to: carrier, followerPose: followerPose, carrierPose: carrierPose
        )
    }

    /// Puts `rider` in its seat on `vehicle`, as `SetVehicle` does.
    @discardableResult
    public func board(_ rider: ReferenceKey, on vehicle: ReferenceKey) -> Bool {
        lastPoses[rider] = nil
        return core.board(rider, on: vehicle)
    }

    /// Seats `rider` on the horse's saddle bone, facing the way the horse faces.
    @discardableResult
    public func seat(_ rider: ReferenceKey, on horse: ReferenceKey, bone: String) -> Bool {
        lastPoses[rider] = nil
        return core.seat(rider, on: horse, bone: bone)
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

    public func detach(_ follower: ReferenceKey) {
        guard core.links[follower] != nil else { return }
        if let pose = lastPoses[follower] {
            world?.vehicleFollowerRests(follower, at: pose)
        }
        core.detach(follower)
        lastPoses[follower] = nil
    }

    /// Every follower and carrier, read before `core` changes so the ground port
    /// does not read `core` while it is being written.
    private var linkedReferences: Set<ReferenceKey> {
        Set(core.links.flatMap { [$0.key, $0.value.carrier] })
    }

    public func advance() {
        guard let world else { return }
        guard !core.links.isEmpty else {
            if hasDeltas {
                world.publishVehiclePoses([:])
                world.publishCarriedPoses([:])
                hasDeltas = false
            }
            return
        }
        loadWheels(world: world)
        let linked = linkedReferences
        lastPoses = core.advance(
            base: { world.vehiclePose(of: $0) },
            bone: { world.vehicleBone(of: $0, named: $1) },
            ground: { world.vehicleGround(at: $0, excluding: linked) }
        )
        var placements: [UInt32: float4x4] = [:]
        for (key, pose) in lastPoses {
            if key == .player {
                world.placePlayer(at: pose)
            } else if let formID = world.vehicleFormID(of: key) {
                world.vehicleFollowerMoved(key, to: pose)
                placements[formID] = VehicleCore.matrix(pose)
            }
        }
        for (key, link) in core.links {
            if case let .towed(tow) = link.seat {
                world.spinVehicleWheels(of: key, rolled: tow.rolled)
            }
        }
        world.publishVehiclePoses(placements)
        world.publishCarriedPoses(lastPoses.filter { $0.key != .player })
        hasDeltas = true
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
