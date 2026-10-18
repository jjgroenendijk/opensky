// What the vehicle coordinator asks the app to do. See docs/engine/coordinators.md.

import OpenSkyFormatsESM
import OpenSkyWorldState
import simd

/// One change to the session outside the vehicle rules.
nonisolated public enum VehicleCommand: Equatable, Sendable {
    /// Placements by FormID; the renderer turns them into deltas against its build.
    case publishVehiclePoses([UInt32: float4x4])
    /// Every follower but the player, so other systems read where it rides.
    case publishCarriedPoses([ReferenceKey: ReferenceTransformOverride])
    /// Every carrier and follower of a link, which do not collide with the vehicles.
    case publishLinks(Set<ReferenceKey>)
    case placePlayer(ReferenceTransformOverride)
    /// A follower that is not the player is at the pose this frame.
    case followerMoved(ReferenceKey, to: ReferenceTransformOverride)
    /// A follower left its carrier and now rests at the pose.
    case followerRests(ReferenceKey, at: ReferenceTransformOverride)
    /// Turns the follower's wheels for the distance rolled since the link.
    case spinWheels(ReferenceKey, rolled: Float)
}
