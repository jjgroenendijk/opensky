// The vehicle rules publish where riders and carts are; the streamer keeps them so
// the NPC movement and the collision passes read one copy.

public import OpenSkyFormatsESM
public import OpenSkyWorldState
public import simd

extension CellStreamer {
    public func publishCarriedPoses(_ poses: [ReferenceKey: ReferenceTransformOverride]) {
        npcMovementState.carried = poses
    }

    public func publishVehicleLinks(_ linked: Set<ReferenceKey>) {
        npcMovementState.vehicleLinkedActors = linked
    }

    public func setVehiclePose(_ pose: float4x4, for formID: FormID) {
        npcMovementState.vehiclePoses[formID] = pose
    }
}
