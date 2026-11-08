public import OpenSkyFormatsESM
public import OpenSkyWorldState
public import simd

/// What the world adapters use of `CellStreamerNPCMovementState`.
public protocol CellStreamerNPCMovementStatePort {
    var carried: [ReferenceKey: ReferenceTransformOverride] { get }
    var vehicleLinkedActors: Set<ReferenceKey> { get }
    var vehiclePoses: [FormID: float4x4] { get }
}
