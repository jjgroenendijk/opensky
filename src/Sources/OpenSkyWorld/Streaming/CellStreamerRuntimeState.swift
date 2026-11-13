// How a world-state mutation becomes a cell rebuild. Every build carries the
// snapshot sequence it was built from, and every mutation raises its cell's
// mutation sequence. A resident scene is current while `stateSequence >=
// cellMutationSequence`. An in-flight build is always integrated; if it predates
// a mutation, a rebuild is queued. A rebuild is a whole cell, so it is
// idempotent. See docs/engine/runtime-state.md.

public import OpenSkyCells
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyTerrain
public import OpenSkyWorldState
import simd

extension CellStreamer.RuntimeStateSteps {
    /// Records a world-state mutation and schedules the rebuilds that make it
    /// visible. Call it on the main thread right after the store journals it.
    /// A nil `location` rebuilds every resident cell, because the streamer cannot
    /// tell which one holds the reference.
    public func noteStateMutation(in location: CellSceneLocation?, sequence: UInt64) {
        guard
            !streamer.isRecordingSettledBody,
            !streamer.actors.noteNPCRestMutation(sequence: sequence) else { return }
        switch location {
        case let .exterior(coordinate):
            noteExteriorMutation(coordinate, sequence: sequence)
        case let .interior(formID):
            noteInteriorMutation(formID, sequence: sequence)
        case nil:
            noteUnattributedMutation(sequence: sequence)
        }
    }

    /// A write that names no cell rebuilds the resident cells that hold `key`. A
    /// persistent reference can sit in more than one. When none holds it, such as a
    /// spawned reference, every resident cell rebuilds, as for an unattributed write.
    public func noteStateMutation(of key: ReferenceKey, sequence: UInt64) {
        guard
            !streamer.isRecordingSettledBody,
            !streamer.actors.noteNPCRestMutation(sequence: sequence) else { return }
        noteDistantLODMutation(of: key)
        let holders = streamer.composition.cellCoordinates(holding: key)
        let interiorHolds = streamer.interiorScene?.references[key] != nil
        guard !holders.isEmpty || interiorHolds else {
            noteUnattributedMutation(sequence: sequence)
            return
        }
        for coordinate in holders {
            noteExteriorMutation(coordinate, sequence: sequence)
        }
        if interiorHolds {
            streamer.interiorMutationSequence = max(streamer.interiorMutationSequence, sequence)
        }
    }

    private func noteExteriorMutation(_ coordinate: CellCoordinate, sequence: UInt64) {
        recordMutationSequence(coordinate, sequence: sequence)
        requestRebuild(coordinate)
    }

    private func noteInteriorMutation(_ formID: FormID, sequence: UInt64) {
        guard
            case let .interior(current)? = streamer.interiorScene?.location,
            current == formID
        else {
            return
        }
        streamer.interiorMutationSequence = max(streamer.interiorMutationSequence, sequence)
    }

    /// An unattributed mutation could touch any loaded reference, so every
    /// resident cell (and the interior, when one owns the view) is rebuilt.
    /// This is the correctness-first choice; a narrower answer needs the store
    /// to attribute its writes, not a cleverer guess here.
    private func noteUnattributedMutation(sequence: UInt64) {
        for coordinate in streamer.core.resident.sorted(by: Self.isOrderedBefore) {
            recordMutationSequence(coordinate, sequence: sequence)
            requestRebuild(coordinate)
        }
        if streamer.interiorScene != nil {
            streamer.interiorMutationSequence = max(streamer.interiorMutationSequence, sequence)
        }
    }

    /// An enable change reaches every child of the reference. A resident cell whose
    /// references name it as `XESP` parent rebuilds. Matching by object ID may
    /// rebuild a cell too many, never one too few.
    public func noteEnableParentMutation(_ key: ReferenceKey, sequence: UInt64) {
        guard case let .plugin(_, objectID) = key else { return }
        noteDistantLODMutation(of: key)
        func dependsOnKey(_ scene: CellScene) -> Bool {
            scene.references.sortedEntries()
                .contains { $0.enableParent?.parent.objectID == objectID }
                || scene.hazards.contains { $0.enableParent?.parent.objectID == objectID }
        }
        for (coordinate, scene) in streamer.composition.cells where dependsOnKey(scene) {
            recordMutationSequence(coordinate, sequence: sequence)
            requestRebuild(coordinate)
        }
        if let interiorScene = streamer.interiorScene, dependsOnKey(interiorScene) {
            streamer.interiorMutationSequence = max(streamer.interiorMutationSequence, sequence)
        }
    }

    /// A ring that draws `key`, or a child of it, with its full model is built again.
    private func noteDistantLODMutation(of key: ReferenceKey) {
        guard
            case let .plugin(_, objectID) = key,
            streamer.composition.distantLOD?.watchedObjectIDs.contains(objectID) == true,
            streamer.requestedLODCenter == streamer.grid.center
        else { return }
        streamer.requestedLODCenter = nil
    }

    private func recordMutationSequence(_ coordinate: CellCoordinate, sequence: UInt64) {
        streamer.cellMutationSequence[coordinate] = max(
            streamer.cellMutationSequence[coordinate] ?? 0,
            sequence
        )
    }

    /// Rebuilds a resident exterior cell, as when a reference it draws moved away.
    public func requestRebuild(of location: CellSceneLocation) {
        guard case let .exterior(coordinate) = location else { return }
        requestRebuild(coordinate)
    }

    /// Queues one rebuild, deduplicating against requests already queued. A
    /// cell that is not accounted for at all is skipped: it is neither drawn
    /// nor being built, so a return visit rebuilds it from the store anyway.
    private func requestRebuild(_ coordinate: CellCoordinate) {
        guard
            streamer.core.accountedCells.contains(coordinate),
            !streamer.rebuildRequests.contains(coordinate) else { return }
        streamer.rebuildRequests.append(coordinate)
    }

    /// Deterministic order for the unattributed fan-out, so a test and a
    /// session see rebuilds queued in the same order.
    private static func isOrderedBefore(_ lhs: CellCoordinate, _ rhs: CellCoordinate) -> Bool {
        (lhs.x, lhs.y) < (rhs.x, rhs.y)
    }

    // MARK: - Reconciling rebuilds with completed builds

    /// Re-queues a rebuild when the scene that just integrated was built from
    /// state older than the newest mutation for its cell. This is the only
    /// place the in-flight race is resolved, and it covers both directions of
    /// it: a mutation that arrived while the first build ran, and a mutation
    /// that arrived while an earlier rebuild ran.
    public func requeueRebuildIfStateMoved(_ coordinate: CellCoordinate, scene: CellScene) {
        guard
            let wanted = streamer.cellMutationSequence[coordinate], scene.stateSequence < wanted,
            !streamer.rebuildRequests.contains(coordinate) else { return }
        streamer.rebuildRequests.append(coordinate)
    }

    /// Drops rebuild bookkeeping for cells the grid no longer accounts for.
    /// Unloading is not a state change — state lives only in the store — so
    /// there is nothing to preserve here: a returning cell is rebuilt from
    /// plugin bytes plus the current snapshot, which reapplies the delta on
    /// its own. Dropping the pending rebuild leaves no ghost dispatch.
    public func pruneRebuildState() {
        let accounted = streamer.core.accountedCells
        streamer.rebuildRequests.removeAll { !accounted.contains($0) }
        streamer.cellMutationSequence = streamer.cellMutationSequence
            .filter { accounted.contains($0.key) }
    }

    // MARK: - Interior rebuilds

    /// Rebuilds the current interior when a mutation has outrun it. An interior
    /// only arrives through a door transition, so this re-runs that transition
    /// against a fresh snapshot. A rebuild passes no camera, so the player stays
    /// where they stand.
    public func dispatchInteriorRebuildIfNeeded() {
        guard
            streamer.transitionInFlight == nil, let scene = streamer.interiorScene,
            let door = streamer.doorState
                .interiorSourceDoor,
            scene.stateSequence < streamer.interiorMutationSequence else { return }
        streamer.transitionInFlight = door
        streamer.interiorRebuildInFlight = true
        streamer.runner.enqueueDoorTransition(from: door, state: streamer.stateSource())
    }

    // MARK: - Inspection (tests + streaming verification)

    /// Rebuild requests queued but not yet dispatched.
    var queuedRebuildCount: Int {
        streamer.rebuildRequests.count
    }

    /// Resident cells with a rebuild currently in flight.
    var rebuildingCellCount: Int {
        streamer.core.rebuilding.count
    }

    /// Runtime references retained by the scenes currently owning the view.
    /// An interior owns the view alone when one is loaded, which
    /// is the same precedence `referenceEntry(key:)` uses, so a lookup that
    /// succeeds is always counted here.
    public var residentReferenceCount: Int {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.references.count
        }
        return streamer.composition.cells.values.reduce(0) { $0 + $1.references.count }
    }

    /// The cell the player is currently in, which is where anything they spawn
    /// belongs. An interior owns the view alone when one is
    /// loaded, matching the precedence every other lookup here uses;
    /// otherwise it is the exterior grid center. Nil only before the first
    /// cell has streamed in, when there is nowhere to put anything.
    var currentCellLocation: CellSceneLocation? {
        if let interiorScene = streamer.interiorScene {
            return interiorScene.location
        }
        return streamer.composition
            .cells[streamer.grid.center] == nil ? nil : .exterior(streamer.grid.center)
    }
}

extension CellStreamer.RuntimeStateSteps {
    /// Builds read the store's snapshot, a mutation rebuilds its cell, and a
    /// settled body persists as a transform override. The store outlives the
    /// streamer, so only the streamer is held weakly.
    public func bind(to store: WorldStateStore) {
        streamer.stateSource = { store.snapshot() }
        store.onMutation = { [weak streamer] location, sequence in
            streamer?.runtimeStates.noteStateMutation(in: location, sequence: sequence)
        }
        store.onUnplacedMutation = { [weak streamer] key, sequence in
            streamer?.runtimeStates.noteStateMutation(of: key, sequence: sequence)
        }
        store.onReferenceMutation = { [weak streamer] key, kind, sequence in
            guard kind == .enableState else { return }
            streamer?.runtimeStates.noteEnableParentMutation(key, sequence: sequence)
        }
        streamer.events.onBodySettled = { [weak streamer] key, transform, placingCell in
            streamer?.isRecordingSettledBody = true
            store.set(transform, for: key, in: placingCell)
            streamer?.isRecordingSettledBody = false
        }
    }
}
