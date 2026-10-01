// How a world-state mutation becomes a cell rebuild. Every build carries the
// snapshot sequence it was built from, and every mutation raises its cell's
// mutation sequence. A resident scene is current while `stateSequence >=
// cellMutationSequence`. An in-flight build is always integrated; if it predates
// a mutation, a rebuild is queued. A rebuild is a whole cell, so it is
// idempotent. See docs/engine/runtime-state.md.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import simd

extension CellStreamer {
    /// Records a world-state mutation and schedules the rebuilds that make it
    /// visible. Call it on the main thread right after the store journals it.
    /// A nil `location` rebuilds every resident cell, because the streamer cannot
    /// tell which one holds the reference.
    public func noteStateMutation(in location: CellSceneLocation?, sequence: UInt64) {
        switch location {
        case let .exterior(coordinate):
            noteExteriorMutation(coordinate, sequence: sequence)
        case let .interior(formID):
            noteInteriorMutation(formID, sequence: sequence)
        case nil:
            noteUnattributedMutation(sequence: sequence)
        }
    }

    private func noteExteriorMutation(_ coordinate: CellCoordinate, sequence: UInt64) {
        recordMutationSequence(coordinate, sequence: sequence)
        requestRebuild(coordinate)
    }

    private func noteInteriorMutation(_ formID: FormID, sequence: UInt64) {
        guard case let .interior(current)? = interiorScene?.location, current == formID else {
            return
        }
        interiorMutationSequence = max(interiorMutationSequence, sequence)
    }

    /// An unattributed mutation could touch any loaded reference, so every
    /// resident cell (and the interior, when one owns the view) is rebuilt.
    /// This is the correctness-first choice; a narrower answer needs the store
    /// to attribute its writes, not a cleverer guess here.
    private func noteUnattributedMutation(sequence: UInt64) {
        for coordinate in core.resident.sorted(by: Self.isOrderedBefore) {
            recordMutationSequence(coordinate, sequence: sequence)
            requestRebuild(coordinate)
        }
        if interiorScene != nil {
            interiorMutationSequence = max(interiorMutationSequence, sequence)
        }
    }

    private func recordMutationSequence(_ coordinate: CellCoordinate, sequence: UInt64) {
        cellMutationSequence[coordinate] = max(
            cellMutationSequence[coordinate] ?? 0,
            sequence
        )
    }

    /// Queues one rebuild, deduplicating against requests already queued. A
    /// cell that is not accounted for at all is skipped: it is neither drawn
    /// nor being built, so a return visit rebuilds it from the store anyway.
    private func requestRebuild(_ coordinate: CellCoordinate) {
        guard core.accountedCells.contains(coordinate) else { return }
        guard !rebuildRequests.contains(coordinate) else { return }
        rebuildRequests.append(coordinate)
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
        guard let wanted = cellMutationSequence[coordinate], scene.stateSequence < wanted else {
            return
        }
        guard !rebuildRequests.contains(coordinate) else { return }
        rebuildRequests.append(coordinate)
    }

    /// Drops rebuild bookkeeping for cells the grid no longer accounts for.
    /// Unloading is not a state change — state lives only in the store — so
    /// there is nothing to preserve here: a returning cell is rebuilt from
    /// plugin bytes plus the current snapshot, which reapplies the delta on
    /// its own. Dropping the pending rebuild leaves no ghost dispatch.
    public func pruneRebuildState() {
        let accounted = core.accountedCells
        rebuildRequests.removeAll { !accounted.contains($0) }
        cellMutationSequence = cellMutationSequence.filter { accounted.contains($0.key) }
    }

    // MARK: - Interior rebuilds

    /// Rebuilds the current interior when a mutation has outrun it. An interior
    /// only arrives through a door transition, so this re-runs that transition
    /// against a fresh snapshot. A rebuild passes no camera, so the player stays
    /// where they stand.
    public func dispatchInteriorRebuildIfNeeded() {
        guard transitionInFlight == nil, let scene = interiorScene, let door = interiorSourceDoor
        else { return }
        guard scene.stateSequence < interiorMutationSequence else { return }
        transitionInFlight = door
        interiorRebuildInFlight = true
        runner.enqueueDoorTransition(from: door, state: stateSource())
    }

    // MARK: - Inspection (tests + streaming verification)

    /// Rebuild requests queued but not yet dispatched.
    public var queuedRebuildCount: Int {
        rebuildRequests.count
    }

    /// Resident cells with a rebuild currently in flight.
    public var rebuildingCellCount: Int {
        core.rebuilding.count
    }

    /// Runtime references retained by the scenes currently owning the view.
    /// An interior owns the view alone when one is loaded, which
    /// is the same precedence `referenceEntry(key:)` uses, so a lookup that
    /// succeeds is always counted here.
    public var residentReferenceCount: Int {
        if let interiorScene {
            return interiorScene.references.count
        }
        return composition.cells.values.reduce(0) { $0 + $1.references.count }
    }

    /// The cell the player is currently in, which is where anything they spawn
    /// belongs. An interior owns the view alone when one is
    /// loaded, matching the precedence every other lookup here uses;
    /// otherwise it is the exterior grid center. Nil only before the first
    /// cell has streamed in, when there is nowhere to put anything.
    public var currentCellLocation: CellSceneLocation? {
        if let interiorScene {
            return interiorScene.location
        }
        return composition.cells[grid.center] == nil ? nil : .exterior(grid.center)
    }
}

extension CellStreamer {
    /// Builds read the store's snapshot, a mutation rebuilds its cell, and a
    /// settled body persists as a transform override. The store outlives the
    /// streamer, so only the streamer is held weakly.
    public func bind(to store: WorldStateStore) {
        stateSource = { store.snapshot() }
        store.onMutation = { [weak self] location, sequence in
            self?.noteStateMutation(in: location, sequence: sequence)
        }
        onBodySettled = { key, transform, placingCell in
            store.set(transform, for: key, in: placingCell)
        }
    }
}
