// Streaming bookkeeping core (todo 3.2 async build): the pure decision half of
// CellStreamer. Tracks which grid slots are resident, in flight, void (no CELL
// record) or failed (build threw), so the grid manager never re-requests a
// slot it already handled. No Metal, no async, no I/O -- a value type driven
// by CellGridDiffs and build completions, unit-tested without game data or a
// GPU. See docs/engine/cell-streaming.md.

import simd

/// What CellStreamer must drive after applying one grid diff: coordinates to
/// hand the builder (each requested exactly once) and resident coordinates to
/// drop from the composition (their cells left the grid).
nonisolated struct StreamActions: Equatable {
    let requests: [CellCoordinate]
    let removals: [CellCoordinate]
}

nonisolated struct CellStreamCore {
    /// How a completed build resolved. Payload-free: the core tracks only
    /// coordinates; CellStreamer carries the built CellScene for `.success`.
    enum BuildKind: Equatable {
        /// Built a drawable cell.
        case success
        /// No CELL at the grid slot (void exterior slot, `cellNotFound`).
        case void
        /// Build threw for any other reason (malformed subtree, missing
        /// worldspace) -- recorded so it is not retried every frame.
        case failure
    }

    /// Outcome of folding one completed build back in.
    enum IntegrationResult: Equatable {
        /// New resident cell -- caller adds it to the composition + recomposes.
        case integrated
        /// Recorded void; nothing to draw, no recompose.
        case recordedVoid
        /// Recorded failed; nothing to draw, no recompose.
        case recordedFailed
        /// The slot was unloaded (recenter) while its build ran -- the result
        /// is stale, dropped. Out-of-order / late completions land here.
        case discardedStale
    }

    /// Built cells currently resident (mirror of the composition's keys).
    private(set) var resident: Set<CellCoordinate> = []
    /// Requested, build dispatched, not yet integrated.
    private(set) var inFlight: Set<CellCoordinate> = []
    /// Slots with no CELL record -- remembered so the grid never re-requests
    /// them (retry storm), forgotten only when the slot leaves the grid.
    private(set) var void: Set<CellCoordinate> = []
    /// Slots whose build threw -- same no-retry treatment as void.
    private(set) var failed: Set<CellCoordinate> = []

    /// Everything the grid manager must treat as already handled, so
    /// `CellGridManager.update` never re-emits these in `loads`. Feeding
    /// void + failed here (not just resident + in-flight) is what stops the
    /// per-frame retry storm on empty or broken slots.
    var accountedCells: Set<CellCoordinate> {
        resident.union(inFlight).union(void).union(failed)
    }

    /// Seeds one synchronously-built destination exterior cell after a door
    /// transition. Existing bookkeeping remains valid while streaming was
    /// suspended; destination becomes resident before next grid diff.
    mutating func seedResident(_ coordinate: CellCoordinate) {
        inFlight.remove(coordinate)
        void.remove(coordinate)
        failed.remove(coordinate)
        resident.insert(coordinate)
    }

    /// Folds one grid diff into the bookkeeping. `loads` (already excluding
    /// accounted cells, by construction of `accountedCells`) become fresh
    /// in-flight requests. `unloads` forget the slot from every set -- a
    /// resident cell is dropped from the composition, a void/failed/in-flight
    /// slot is simply forgotten so a return visit rebuilds it fresh (an
    /// in-flight build still running is left to complete and then be
    /// discarded as stale, since it is no longer in `inFlight`).
    mutating func apply(diff: CellGridDiff) -> StreamActions {
        for coordinate in diff.loads {
            inFlight.insert(coordinate)
        }
        var removals: [CellCoordinate] = []
        for coordinate in diff.unloads {
            if resident.remove(coordinate) != nil {
                removals.append(coordinate)
            }
            inFlight.remove(coordinate)
            void.remove(coordinate)
            failed.remove(coordinate)
        }
        return StreamActions(requests: Array(diff.loads), removals: removals)
    }

    /// Records a completed build. A coordinate no longer in `inFlight` was
    /// unloaded mid-flight (recenter) -> `.discardedStale`; this is also how
    /// a duplicate late completion for an already-integrated slot is ignored.
    /// Otherwise the slot leaves `inFlight` and lands in the matching set.
    mutating func integrate(
        coordinate: CellCoordinate,
        kind: BuildKind
    ) -> IntegrationResult {
        guard inFlight.remove(coordinate) != nil else {
            return .discardedStale
        }
        switch kind {
        case .success:
            resident.insert(coordinate)
            return .integrated
        case .void:
            void.insert(coordinate)
            return .recordedVoid
        case .failure:
            failed.insert(coordinate)
            return .recordedFailed
        }
    }
}
