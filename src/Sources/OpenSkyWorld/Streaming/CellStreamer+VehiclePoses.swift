// The vehicle rules publish where riders and carts are; the streamer keeps them so
// the NPC movement and the collision passes read one copy.

import OpenSkyCells
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyWorldState
public import simd

extension CellStreamer.ActorSteps {
    public func publishCarriedPoses(_ poses: [ReferenceKey: ReferenceTransformOverride]) {
        streamer.npcMovementState.carried = poses
    }

    public func publishVehicleLinks(_ linked: Set<ReferenceKey>) {
        streamer.npcMovementState.vehicleLinkedActors = linked
    }

    public func setVehiclePose(_ pose: float4x4, for formID: FormID) {
        streamer.npcMovementState.vehiclePoses[formID] = pose
    }

    /// The streamer this part belongs to, for a hook that must hold it weakly.
    public var cellStreamer: CellStreamer {
        streamer
    }
}
