// The NPC movers of the resident cells: walking, facing, resting, and riding.

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

/// The NPC movers of the resident cells: walking, facing, resting, and riding. Part of
/// `CellStreamerPort`.
public protocol CellStreamerActorsPort {
    associatedtype NPCMovementRuntime: NPCMovementRuntimePort
    @discardableResult func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>) -> Bool
    @discardableResult func knockActor(_ actor: ReferenceKey, velocity: SIMD3<Float>) -> Bool
    @discardableResult func moveActor(_ request: ActorMoveRequest) -> NPCMoveCommandResult
    func moveStandingActor(
        _ actor: ReferenceKey,
        by displacement: SIMD2<Float>,
        turning headingTurn: Float
    )
    var npcBodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)? { get }
    var npcMovement: NPCMovementRuntime { get }
    func npcMovementReadouts() -> [NPCMovementReadout]
    var npcMovementSpeeds: ((ReferenceKey) -> MovementType.Speeds?)? { get }
    func publishCarriedPoses(_ poses: [ReferenceKey: ReferenceTransformOverride])
    func publishVehicleLinks(_ linked: Set<ReferenceKey>)
    func setVehiclePose(_ pose: float4x4, for formID: FormID)
    func npcTransform(for actor: ReferenceKey) -> ReferenceTransformOverride?
    func persistNPCMovementForSave()
    func placeStandingActor(_ actor: ReferenceKey, at transform: ReferenceTransformOverride)
    @discardableResult func releaseActorFacing(_ actor: ReferenceKey) -> Bool
    @discardableResult func releaseRiddenActor(_ actor: ReferenceKey) -> Bool
    func restActor(_ actor: ReferenceKey, at transform: ReferenceTransformOverride)
    func riddenHold(of actor: ReferenceKey) -> NPCRiddenHold?
    func steerRiddenActor(_ actor: ReferenceKey, to feet: SIMD3<Float>, yaw: Float)
    @discardableResult func stopActor(_ actor: ReferenceKey) -> Bool
    func takeRiddenActor(_ actor: ReferenceKey) -> NPCRiddenHold?
    func turnActor(
        _ actor: ReferenceKey,
        toHeading heading: Float,
        within tolerance: Float
    ) -> Float?
    func isActorWalking(_ actor: ReferenceKey) -> Bool
}

extension CellStreamerActorsPort {
    @discardableResult public func moveActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool = false,
        gait: LocomotionGait? = nil, runSlowdown: FollowSettings? = nil,
        walkRunBlend: Float? = nil
    ) -> NPCMoveCommandResult {
        var request = ActorMoveRequest(actor, to: point)
        request.direct = direct
        request.gait = gait
        request.runSlowdown = runSlowdown
        request.walkRunBlend = walkRunBlend
        return moveActor(request)
    }
}
