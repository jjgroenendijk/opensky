// The CellStreamerPort and PapyrusWorldReferenceSource calls, each answered by the part that owns
// it.

import Foundation
public import OpenSkyActorPresentation
import OpenSkyAudio
public import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTerrain
public import OpenSkyWorldInterface
public import OpenSkyWorldState
public import simd

extension CellStreamer {
    public func activateChildren(of key: ReferenceKey) -> [ActivateChild] {
        residents.activateChildren(of: key)
    }

    public func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
        residents.referenceEntry(formID: formID)
    }

    public func residentEntries() -> [RuntimeReferenceEntry] {
        residents.residentEntries()
    }

    public func pluginPlacement(of key: ReferenceKey) -> PluginPlacement? {
        residents.pluginPlacement(of: key)
    }

    public func residentActorEntries() -> [RuntimeReferenceEntry] {
        residents.residentActorEntries()
    }

    public var residentCellLocations: Set<CellSceneLocation> {
        physics.residentCellLocations
    }

    @discardableResult
    public func requestDoorTransition(from sourceDoor: FormID) -> Bool {
        transitions.requestDoorTransition(from: sourceDoor)
    }

    public func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
        residents.referenceEntry(key: key)
    }

    public func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
        residents.cellLocation(of: key)
    }

    public func requestRebuild(of location: CellSceneLocation) {
        runtimeStates.requestRebuild(of: location)
    }

    public func leaveInterior(camera: SceneCamera) {
        transitions.leaveInterior(camera: camera)
    }

    public var residentReferenceCount: Int {
        runtimeStates.residentReferenceCount
    }

    public var currentCellLocation: CellSceneLocation? {
        runtimeStates.currentCellLocation
    }

    public func setActorProp(_ prop: ActorPropAttachment?, on actor: FormID) {
        props.setActorProp(prop, on: actor)
    }

    public func poseMovingCollision(bones: (UInt32) -> [simd_float4x4]?) {
        props.poseMovingCollision(bones: bones)
    }

    public func residentAnimatedVehicles() -> [CellAnimatedVehicle] {
        props.residentAnimatedVehicles()
    }

    public var startAreaReady: Bool {
        coverage.startAreaReady
    }

    public var inFlightCellCount: Int {
        coverage.inFlightCellCount
    }

    public var pendingCompletionCount: Int {
        coverage.pendingCompletionCount
    }

    public var queuedRequestCount: Int {
        coverage.queuedRequestCount
    }

    public var largeReferenceCount: Int {
        coverage.largeReferenceCount
    }

    public var fullLODReferenceCount: Int {
        coverage.fullLODReferenceCount
    }

    public var generatedTerrainBlockCount: Int {
        coverage.generatedTerrainBlockCount
    }

    public var hiddenLargeReferenceSegments: Int {
        coverage.hiddenLargeReferenceSegments
    }

    public var coverageReadout: CellCoverageReadout {
        CellCoverageReadout(
            center: grid.center, wantedCells: grid.desiredCells,
            drawnCells: composition.coordinates, waitingCells: Set(stagedCells.keys),
            ringCenter: liveLODCenter, ringBuilding: lodRequestHiddenCells != nil,
            ringSwaps: ringSwapCount
        )
    }

    public var isInterior: Bool {
        coverage.isInterior
    }

    public func findPath(_ query: NavigationPathQuery) -> NavigationPathResult {
        navigation.findPath(query)
    }

    public var onDoorTransitionStarted: (() -> Void)? {
        get { events.onDoorTransitionStarted }
        set { events.onDoorTransitionStarted = newValue }
    }

    public var onDoorTransitionFinished: ((CellScene?) -> Void)? {
        get { events.onDoorTransitionFinished }
        set { events.onDoorTransitionFinished = newValue }
    }
}
