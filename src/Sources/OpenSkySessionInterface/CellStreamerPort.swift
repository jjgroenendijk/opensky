public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyPhysics
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

/// What the world adapters use of `CellStreamer`.
public protocol CellStreamerPort: AnyObject, PapyrusWorldReferenceSource {
    associatedtype ActivationGateSeam: ActivationGateSeamPort
    associatedtype CellAnimatedObject: CellAnimatedObjectPort
    associatedtype CellAnimatedVehicle: CellAnimatedVehiclePort
    associatedtype CellAttachment: CellAttachmentPort
    associatedtype CellGridManager: CellGridManagerPort
    associatedtype CellNodeAnimation: CellNodeAnimationPort
    associatedtype CellScene: CellScenePort
    associatedtype CellSceneComposition: CellSceneCompositionPort
    associatedtype CellSequenceDoor: CellSequenceDoorPort
    associatedtype CellStreamerNPCMovementState: CellStreamerNPCMovementStatePort
    associatedtype NPCMovementRuntime: NPCMovementRuntimePort
    associatedtype TalkTargetingSeam: TalkTargetingSeamPort
    func activate(_ target: InteractionTarget, offeringPerkChoices: Bool)
    var activationGate: ActivationGateSeam { get set }
    var actorPoseRevision: UInt64 { get }
    func appearanceSkipReasons(forActor formID: FormID) -> [String]
    func collisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape]
    var composition: CellSceneComposition { get set }
    var currentCellLocation: CellSceneLocation? { get }
    var dynamicBodies: DynamicBodyWorld { get set }
    func enterWorldspace(_ editorID: String, camera: SceneCamera)
    @discardableResult func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>) -> Bool
    func findPath(_ query: NavigationPathQuery) -> NavigationPathResult
    var fullLODReferenceCount: Int { get }
    var generatedTerrainBlockCount: Int { get }
    var grid: CellGridManager { get }
    var hiddenLargeReferenceSegments: Int { get }
    var inFlightCellCount: Int { get }
    func interactionName(reference: FormID) -> String?
    var interactionTarget: InteractionTarget? { get }
    var interiorMutationSequence: UInt64 { get }
    var interiorRebuildInFlight: Bool { get set }
    var interiorScene: CellScene? { get }
    func inventoryHolder(of key: ReferenceKey) -> InventoryHolder?
    var isHeld: Bool { get set }
    var isInterior: Bool { get }
    @discardableResult func knockActor(_ actor: ReferenceKey, velocity: SIMD3<Float>) -> Bool
    var largeReferenceCount: Int { get }
    func leaveInterior(camera: SceneCamera)
    @discardableResult func moveActor(_ request: ActorMoveRequest) -> NPCMoveCommandResult
    func moveStandingActor(
        _ actor: ReferenceKey,
        by displacement: SIMD2<Float>,
        turning headingTurn: Float
    )
    func nearestActorEntry(to position: SIMD3<Float>) -> RuntimeReferenceEntry?
    func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit?
    var npcBodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)? { get }
    var npcMovement: NPCMovementRuntime { get }
    func npcMovementReadouts() -> [NPCMovementReadout]
    var npcMovementSpeeds: ((ReferenceKey) -> MovementType.Speeds?)? { get }
    var npcMovementState: CellStreamerNPCMovementState { get set }
    func publishCarriedPoses(_ poses: [ReferenceKey: ReferenceTransformOverride])
    func publishVehicleLinks(_ linked: Set<ReferenceKey>)
    func setVehiclePose(_ pose: float4x4, for formID: FormID)
    func npcTransform(for actor: ReferenceKey) -> ReferenceTransformOverride?
    var onCellAttached: FrameSchedule<CellAttachStep, CellAttachment> { get }
    func registerCellAttached(_ phase: CellAttachStep, _ step: @escaping (CellAttachment) -> Void)
    var onCellDetached: FrameSchedule<CellDetachStep, CellSceneLocation> { get }
    var onInteraction: FrameSchedule<InteractionStep, InteractionEvent> { get }
    var pendingCompletionCount: Int { get }
    func persistNPCMovementForSave()
    func placeStandingActor(_ actor: ReferenceKey, at transform: ReferenceTransformOverride)
    var placedRecords: PlacedRecordLookup? { get }
    var playerRegions: [FormID] { get }
    func poseMovingCollision(bones: (UInt32) -> [simd_float4x4]?)
    var queuedRequestCount: Int { get }
    @discardableResult func releaseActorFacing(_ actor: ReferenceKey) -> Bool
    @discardableResult func releaseRiddenActor(_ actor: ReferenceKey) -> Bool
    @discardableResult func requestDoorTransition(_ door: PlacedDoor?) -> Bool
    @discardableResult func requestDoorTransition(from sourceDoor: FormID) -> Bool
    func requestRebuild(of location: CellSceneLocation)
    func residentActorEntry(key: ReferenceKey) -> RuntimeReferenceEntry?
    func residentActorPlacement(key: ReferenceKey) -> ResidentActorPlacement?
    func residentAnimatedObjects() -> [CellAnimatedObject]
    func residentAnimatedVehicles() -> [CellAnimatedVehicle]
    var residentCellLocations: Set<CellSceneLocation> { get }
    func residentInteraction(reference: FormID) -> PlacedInteraction?
    var residentInteractions: [PlacedInteraction] { get }
    func residentNodeAnimations() -> [CellNodeAnimation]
    var residentReferenceCount: Int { get }
    func residentReferenceIndex() -> RuntimeReferenceIndex
    func residentScene(at location: CellSceneLocation) -> CellScene?
    var residentScenes: [CellScene] { get }
    func residentReferencePlaces(location: (CellLocationKey) -> ResolvedFormID?) -> ReferencePlaces
    func residentSequenceDoors() -> [CellSequenceDoor]
    func restActor(_ actor: ReferenceKey, at transform: ReferenceTransformOverride)
    func riddenHold(of actor: ReferenceKey) -> NPCRiddenHold?
    func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample?
    func sampleWaterHeight(at position: SIMD2<Float>) -> Float?
    var sequenceDoorLeaves: [UInt32: [float4x4]] { get set }
    func setActorProp(_ prop: ActorPropAttachment?, on actor: FormID)
    var startAreaReady: Bool { get }
    func staticCollisionBlocks(ray: InteractionRay) -> Bool
    func staticCollisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape]
    func steerRiddenActor(_ actor: ReferenceKey, to feet: SIMD3<Float>, yaw: Float)
    @discardableResult func stopActor(_ actor: ReferenceKey) -> Bool
    func takeRiddenActor(_ actor: ReferenceKey) -> NPCRiddenHold?
    var talk: TalkTargetingSeam { get set }
    func topCollisionSurface(at position: SIMD2<Float>) -> SIMD3<Float>?
    var transitionInFlight: FormID? { get }
    func turnActor(
        _ actor: ReferenceKey,
        toHeading heading: Float,
        within tolerance: Float
    ) -> Float?
    func water(at point: SIMD3<Float>) -> WaterReading?
    var worldspaceEditorID: String { get }
    var cachedAssetCounts: CachedAssetCounts? { get }

    func isActorWalking(_ actor: ReferenceKey) -> Bool

    func moveStart(to position: SIMD3<Float>)
}

/// The default arguments a protocol requirement cannot carry.
extension CellStreamerPort {
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

    public func activate(_ target: InteractionTarget) {
        activate(target, offeringPerkChoices: true)
    }
}

/// One move order, so the port requirement stays under the parameter cap.
public struct ActorMoveRequest {
    public var actor: ReferenceKey
    public var point: SIMD3<Float>
    public var direct = false
    public var gait: LocomotionGait?
    public var runSlowdown: FollowSettings?
    public var walkRunBlend: Float?

    public init(_ actor: ReferenceKey, to point: SIMD3<Float>) {
        self.actor = actor
        self.point = point
    }
}
