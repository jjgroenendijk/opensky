import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyPhysics
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What the world adapters use of `CellStreamer`.
public protocol CellStreamerPort: AnyObject, PapyrusWorldReferenceSource {
    associatedtype Actors: CellStreamerActorsPort
    var actors: Actors { get }
    associatedtype Residents: CellStreamerResidentsPort
    var residents: Residents { get }
    associatedtype Collision: CellStreamerCollisionPort
    var collision: Collision { get }
    associatedtype Events: CellStreamerEventsPort
    var events: Events { get }
    associatedtype ActivationGateSeam: ActivationGateSeamPort
    associatedtype CellAnimatedVehicle: CellAnimatedVehiclePort
    associatedtype CellAttachment: CellAttachmentPort
    associatedtype CellGridManager: CellGridManagerPort
    associatedtype CellScene: CellScenePort
    associatedtype CellSceneComposition: CellSceneCompositionPort
    associatedtype TalkTargetingSeam: TalkTargetingSeamPort
    var activationGate: ActivationGateSeam { get set }
    var actorPoseRevision: UInt64 { get }
    var composition: CellSceneComposition { get set }
    var currentCellLocation: CellSceneLocation? { get }
    var dynamicBodies: DynamicBodyWorld { get set }
    func enterWorldspace(_ editorID: String, camera: SceneCamera)
    var fullLODReferenceCount: Int { get }
    var generatedTerrainBlockCount: Int { get }
    var grid: CellGridManager { get }
    var hiddenLargeReferenceSegments: Int { get }
    var coverageReadout: CellCoverageReadout { get }
    var inFlightCellCount: Int { get }
    var interactionTarget: InteractionTarget? { get }
    var interiorMutationSequence: UInt64 { get }
    var interiorRebuildInFlight: Bool { get set }
    var interiorScene: CellScene? { get }
    var isHeld: Bool { get set }
    var isInterior: Bool { get }
    func leaveInterior(camera: SceneCamera)
    func registerCellAttached(_ phase: CellAttachStep, _ step: @escaping (CellAttachment) -> Void)
    var pendingCompletionCount: Int { get }
    var placedRecords: PlacedRecordLookup? { get }
    var playerRegions: [FormID] { get }
    func poseMovingCollision(bones: (UInt32) -> [simd_float4x4]?)
    var queuedRequestCount: Int { get }
    func residentAnimatedVehicles() -> [CellAnimatedVehicle]
    var residentCellLocations: Set<CellSceneLocation> { get }
    var residentReferenceCount: Int { get }
    var sequenceDoorLeaves: [UInt32: [float4x4]] { get set }
    func setActorProp(_ prop: ActorPropAttachment?, on actor: FormID)
    var startAreaReady: Bool { get }
    var talk: TalkTargetingSeam { get set }
    var transitionInFlight: FormID? { get }
    var worldspaceEditorID: String { get }
    var cachedAssetCounts: CachedAssetCounts? { get }

    func moveStart(to position: SIMD3<Float>)
    func findPath(_ query: NavigationPathQuery) -> NavigationPathResult
    var largeReferenceCount: Int { get }
    @discardableResult func requestDoorTransition(from sourceDoor: FormID) -> Bool
    func requestRebuild(of location: CellSceneLocation)
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
