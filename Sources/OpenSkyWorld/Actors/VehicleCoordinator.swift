// The shell of the vehicle rules in `VehicleCore`: reads live poses from the
// session each frame and publishes the followers' draw deltas. The player rider
// is placed, not drawn. See docs/engine/vehicles.md.

import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// What the vehicle coordinator reads from and writes to the session.
@MainActor
public protocol VehicleWorld: AnyObject {
    /// Where the reference is now: a walking actor's live pose, else its placed pose.
    func vehiclePose(of key: ReferenceKey) -> ReferenceTransformOverride?
    /// The FormID and pose the current cell build drew the reference with.
    func vehicleDrawnPose(of key: ReferenceKey)
        -> (formID: UInt32, pose: ReferenceTransformOverride)?
    func publishVehicleDeltas(_ deltas: [UInt32: float4x4])
    func placePlayer(at pose: ReferenceTransformOverride)
    /// A follower left its carrier and now rests at `pose`.
    func vehicleFollowerRests(_ key: ReferenceKey, at pose: ReferenceTransformOverride)
    /// A follower that is not the player is at `pose` this frame.
    func vehicleFollowerMoved(_ key: ReferenceKey, to pose: ReferenceTransformOverride)
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

    /// Seats `rider` on top of `horse`, facing the way the horse faces.
    @discardableResult
    public func seat(_ rider: ReferenceKey, on horse: ReferenceKey, height: Float) -> Bool {
        guard let horsePose = currentPose(of: horse) else { return false }
        let seat = ReferenceTransformOverride(placement: PlacedReference.Placement(
            position: horsePose.position + SIMD3(0, 0, height), rotation: horsePose.rotation
        ))
        return core.attach(rider, to: horse, followerPose: seat, carrierPose: horsePose)
    }

    public func detach(_ follower: ReferenceKey) {
        guard core.links[follower] != nil else { return }
        if let pose = lastPoses[follower] {
            world?.vehicleFollowerRests(follower, at: pose)
        }
        core.detach(follower)
        lastPoses[follower] = nil
    }

    public func advance() {
        guard let world else { return }
        guard !core.links.isEmpty else {
            if hasDeltas {
                world.publishVehicleDeltas([:])
                hasDeltas = false
            }
            return
        }
        lastPoses = core.poses { world.vehiclePose(of: $0) }
        var deltas: [UInt32: float4x4] = [:]
        for (key, pose) in lastPoses {
            if key == .player {
                world.placePlayer(at: pose)
            } else if let drawn = world.vehicleDrawnPose(of: key) {
                world.vehicleFollowerMoved(key, to: pose)
                deltas[drawn.formID] = VehicleCore.matrix(pose) * VehicleCore.matrix(drawn.pose)
                    .inverse
            }
        }
        world.publishVehicleDeltas(deltas)
        hasDeltas = !deltas.isEmpty
    }

    private func currentPose(of key: ReferenceKey) -> ReferenceTransformOverride? {
        lastPoses[key] ?? world?.vehiclePose(of: key)
    }
}
