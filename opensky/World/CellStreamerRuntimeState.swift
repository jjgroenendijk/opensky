// Runtime world-state visibility for the streamer (issue #160, roadmap item
// 10.1.3). Split from CellStreamer.swift so exterior grid scheduling stays
// readable.
//
// Two halves live here. The first is how a store mutation becomes a rebuild
// request: `noteStateMutation(in:sequence:)` is called on the main thread right
// after `WorldStateStore` journals a change, and records the sequence against
// the cell the change was attributed to. The second is how a rebuild is
// reconciled with builds that were already running when the change landed.
//
// Design, in one paragraph. Every dispatched build carries the snapshot
// sequence it was built from on `CellScene.stateSequence`, and every mutation
// raises `cellMutationSequence` for its cell. A resident scene is current
// exactly while `stateSequence >= cellMutationSequence`. That single comparison
// resolves the race where a mutation lands while a build for the same cell is
// already in flight: the in-flight result is always integrated (so the cell is
// drawn as soon as it can be, and the old scene is never left up longer than
// necessary), and if it turns out to predate the mutation, a rebuild is queued
// against a fresh snapshot. Because a rebuild reconstructs the whole cell from
// plugin bytes plus the current snapshot, applying it twice is indistinguishable
// from applying it once — there is no delta to double-apply and none to lose.
//
// Rebuilding whole cells is the intended v1: no per-instance patching, and the
// per-frame budget is unchanged at one integration and one dispatch.
//
// Documented in docs/engine/runtime-state.md.

import simd

extension CellStreamer {
    /// Records a world-state mutation and schedules whatever has to be rebuilt
    /// to make it visible. Call this on the main thread immediately after the
    /// store journals the change.
    ///
    /// - Parameters:
    ///   - location: the cell the mutation was attributed to, or nil when the
    ///     store could not attribute it. An unattributed mutation is treated
    ///     conservatively: every resident cell is rebuilt, because the streamer
    ///     has no cheaper way to tell which one the reference lives in.
    ///   - sequence: the journal sequence a snapshot taken now would carry.
    func noteStateMutation(in location: CellSceneLocation?, sequence: UInt64) {
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
    func requeueRebuildIfStateMoved(_ coordinate: CellCoordinate, scene: CellScene) {
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
    /// its own. Dropping the pending rebuild is therefore the cancellation
    /// the issue asks for, with no ghost dispatch left behind.
    func pruneRebuildState() {
        let accounted = core.accountedCells
        rebuildRequests.removeAll { !accounted.contains($0) }
        cellMutationSequence = cellMutationSequence.filter { accounted.contains($0.key) }
    }

    // MARK: - Interior rebuilds

    /// Rebuilds the interior currently owning the view when a mutation has
    /// outrun it.
    ///
    /// There is no provider entry point that builds an interior cell on its
    /// own: an interior only ever arrives as the destination of a door
    /// transition, so the rebuild re-runs that same transition against a fresh
    /// snapshot. That is the simplest mechanism that is correct, and it reuses
    /// the existing path rather than adding a second one. The one adjustment
    /// is that `apply(transition:sourceDoor:isRebuild:)` passes no camera for a
    /// rebuild, so the swap leaves the player exactly where they are standing
    /// instead of teleporting them back to the door.
    func dispatchInteriorRebuildIfNeeded() {
        guard transitionInFlight == nil, let scene = interiorScene, let door = interiorSourceDoor
        else { return }
        guard scene.stateSequence < interiorMutationSequence else { return }
        transitionInFlight = door
        interiorRebuildInFlight = true
        runner.enqueueDoorTransition(from: door, state: stateSource())
    }

    // MARK: - Inspection (tests + streaming verification)

    /// Rebuild requests queued but not yet dispatched.
    var queuedRebuildCount: Int {
        rebuildRequests.count
    }

    /// Resident cells with a rebuild currently in flight.
    var rebuildingCellCount: Int {
        core.rebuilding.count
    }

    /// The world state the next dispatched build would run against.
    var currentStateSnapshot: WorldStateSnapshot {
        stateSource()
    }
}
