// Shortcuts from the streamer port to the calls of its parts, so a caller writes
// `streamer.moveActor(...)` and does not depend on which part answers it.

public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyInventoryInterface
public import OpenSkyPhysics
public import OpenSkyRenderCore
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

extension CellStreamerPort {
    @discardableResult public func faceActor(
        _ actor: ReferenceKey,
        towards point: SIMD3<Float>
    ) -> Bool {
        actors.faceActor(actor, towards: point)
    }

    public func moveStandingActor(
        _ actor: ReferenceKey,
        by displacement: SIMD2<Float>,
        turning headingTurn: Float
    ) {
        actors.moveStandingActor(actor, by: displacement, turning: headingTurn)
    }

    public var npcBodyHalfExtents: ((ReferenceKey) -> SIMD3<Float>?)? {
        actors.npcBodyHalfExtents
    }

    public var npcMovement: Actors.NPCMovementRuntime {
        actors.npcMovement
    }

    public func npcMovementReadouts() -> [NPCMovementReadout] {
        actors.npcMovementReadouts()
    }

    public func publishCarriedPoses(_ poses: [ReferenceKey: ReferenceTransformOverride]) {
        actors.publishCarriedPoses(poses)
    }

    public func publishVehicleLinks(_ linked: Set<ReferenceKey>) {
        actors.publishVehicleLinks(linked)
    }

    public func setVehiclePose(_ pose: float4x4, for formID: FormID) {
        actors.setVehiclePose(pose, for: formID)
    }

    public func npcTransform(for actor: ReferenceKey) -> ReferenceTransformOverride? {
        actors.npcTransform(for: actor)
    }

    public func persistNPCMovementForSave() {
        actors.persistNPCMovementForSave()
    }

    public func placeStandingActor(
        _ actor: ReferenceKey,
        at transform: ReferenceTransformOverride
    ) {
        actors.placeStandingActor(actor, at: transform)
    }

    @discardableResult public func releaseActorFacing(_ actor: ReferenceKey) -> Bool {
        actors.releaseActorFacing(actor)
    }

    @discardableResult public func releaseRiddenActor(_ actor: ReferenceKey) -> Bool {
        actors.releaseRiddenActor(actor)
    }

    public func restActor(_ actor: ReferenceKey, at transform: ReferenceTransformOverride) {
        actors.restActor(actor, at: transform)
    }

    public func steerRiddenActor(_ actor: ReferenceKey, to feet: SIMD3<Float>, yaw: Float) {
        actors.steerRiddenActor(actor, to: feet, yaw: yaw)
    }

    @discardableResult public func stopActor(_ actor: ReferenceKey) -> Bool {
        actors.stopActor(actor)
    }

    public func takeRiddenActor(_ actor: ReferenceKey) -> NPCRiddenHold? {
        actors.takeRiddenActor(actor)
    }

    public func turnActor(
        _ actor: ReferenceKey,
        toHeading heading: Float,
        within tolerance: Float
    ) -> Float? {
        actors.turnActor(actor, toHeading: heading, within: tolerance)
    }

    public func isActorWalking(_ actor: ReferenceKey) -> Bool {
        actors.isActorWalking(actor)
    }

    public func activate(_ target: InteractionTarget, offeringPerkChoices: Bool) {
        residents.activate(target, offeringPerkChoices: offeringPerkChoices)
    }

    public func appearanceSkipReasons(forActor formID: FormID) -> [String] {
        residents.appearanceSkipReasons(forActor: formID)
    }

    public func interactionName(reference: FormID) -> String? {
        residents.interactionName(reference: reference)
    }

    public func inventoryHolder(of key: ReferenceKey) -> InventoryHolder? {
        residents.inventoryHolder(of: key)
    }

    public func nearestActorEntry(to position: SIMD3<Float>) -> RuntimeReferenceEntry? {
        residents.nearestActorEntry(to: position)
    }

    public func residentActorEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        residents.residentActorEntry(key: key)
    }

    public func residentActorPlacement(key: ReferenceKey) -> ResidentActorPlacement? {
        residents.residentActorPlacement(key: key)
    }

    public func residentInteraction(reference: FormID) -> PlacedInteraction? {
        residents.residentInteraction(reference: reference)
    }

    public var residentInteractions: [PlacedInteraction] {
        residents.residentInteractions
    }

    public func residentReferenceIndex() -> RuntimeReferenceIndex {
        residents.residentReferenceIndex()
    }

    public func residentReferencePlaces(location: (CellLocationKey) -> ResolvedFormID?)
        -> ReferencePlaces
    {
        residents.residentReferencePlaces(location: location)
    }

    public func residentScene(at location: CellSceneLocation) -> Residents.CellScene? {
        residents.residentScene(at: location)
    }

    public func collisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape] {
        collision.collisionCandidates(overlapping: bounds)
    }

    public func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit? {
        collision.nearestCollisionHit(ray: ray)
    }

    public func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample? {
        collision.sampleTerrain(at: position)
    }

    public func staticCollisionBlocks(ray: InteractionRay) -> Bool {
        collision.staticCollisionBlocks(ray: ray)
    }

    public func staticCollisionCandidates(overlapping bounds: ModelBounds)
        -> [StaticCollisionShape]
    {
        collision.staticCollisionCandidates(overlapping: bounds)
    }

    public func topCollisionSurface(at position: SIMD2<Float>) -> SIMD3<Float>? {
        collision.topCollisionSurface(at: position)
    }

    public var onCellDetached: FrameSchedule<CellDetachStep, CellSceneLocation> {
        events.onCellDetached
    }

    public var onInteraction: FrameSchedule<InteractionStep, InteractionEvent> {
        events.onInteraction
    }

    @discardableResult public func moveActor(
        _ actor: ReferenceKey, to point: SIMD3<Float>, direct: Bool = false,
        gait: LocomotionGait? = nil, runSlowdown: FollowSettings? = nil,
        walkRunBlend: Float? = nil
    ) -> NPCMoveCommandResult {
        actors.moveActor(
            actor, to: point, direct: direct, gait: gait, runSlowdown: runSlowdown,
            walkRunBlend: walkRunBlend
        )
    }
}
