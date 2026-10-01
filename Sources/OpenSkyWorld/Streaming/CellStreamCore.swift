// The pure decision half of CellStreamer: which slots are resident, in flight, void (no
// CELL) or failed, so no slot is requested twice. A value type, tested without game data
// or a GPU. See docs/engine/cell-streaming.md.

import OpenSkyFormatsCore
import simd

/// What CellStreamer must drive after applying one grid diff: coordinates to
/// hand the builder (each requested exactly once) and resident coordinates to
/// drop from the composition (their cells left the grid).
nonisolated public struct StreamActions: Equatable, Sendable {
    public let requests: [CellCoordinate]
    public let removals: [CellCoordinate]
}

nonisolated public struct CellStreamCore: Sendable {
    /// How a completed build resolved. Payload-free: the core tracks only
    /// coordinates; CellStreamer carries the built CellScene for `.success`.
    public enum BuildKind: Equatable, Sendable {
        /// Built a drawable cell.
        case success
        /// No CELL at the grid slot (void exterior slot, `cellNotFound`).
        case void
        /// Build threw for any other reason (malformed subtree, missing
        /// worldspace) -- recorded so it is not retried every frame.
        case failure
    }

    /// Outcome of folding one completed build back in.
    public enum IntegrationResult: Equatable, Sendable {
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
    public private(set) var resident: Set<CellCoordinate> = []
    /// Requested, build dispatched, not yet integrated.
    public private(set) var inFlight: Set<CellCoordinate> = []
    /// Slots with no CELL record -- remembered so the grid never re-requests
    /// them (retry storm), forgotten only when the slot leaves the grid.
    public private(set) var void: Set<CellCoordinate> = []
    /// Slots whose build threw -- same no-retry treatment as void.
    public private(set) var failed: Set<CellCoordinate> = []
    /// Resident cells being rebuilt against newer world state. They stay in `resident`
    /// and keep rendering; this marks a completion for them as expected, not stale.
    public private(set) var rebuilding: Set<CellCoordinate> = []

    /// Everything the grid manager must treat as already handled, so
    /// `CellGridManager.update` never re-emits these in `loads`. Feeding
    /// void + failed here (not just resident + in-flight) is what stops the
    /// per-frame retry storm on empty or broken slots.
    public var accountedCells: Set<CellCoordinate> {
        resident.union(inFlight).union(void).union(failed)
    }

    /// Seeds one synchronously-built destination exterior cell after a door
    /// transition. Existing bookkeeping remains valid while streaming was
    /// suspended; destination becomes resident before next grid diff.
    public mutating func seedResident(_ coordinate: CellCoordinate) {
        inFlight.remove(coordinate)
        void.remove(coordinate)
        failed.remove(coordinate)
        rebuilding.remove(coordinate)
        resident.insert(coordinate)
    }

    /// Marks a rebuild for a resident cell. False when the cell is not resident, so no
    /// rebuild is dispatched for an unbuilt or unloaded cell.
    public mutating func beginRebuild(_ coordinate: CellCoordinate) -> Bool {
        guard resident.contains(coordinate) else { return false }
        rebuilding.insert(coordinate)
        return true
    }

    /// Folds one grid diff in. `loads` become in-flight requests; `unloads` are forgotten
    /// everywhere, so a return visit rebuilds. A build still running is discarded as stale.
    public mutating func apply(diff: CellGridDiff) -> StreamActions {
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
            rebuilding.remove(coordinate)
        }
        return StreamActions(requests: Array(diff.loads), removals: removals)
    }

    /// Records a completed build. Not in `inFlight` -> `.discardedStale`. A rebuild that
    /// is drawable replaces the resident scene; a void or failed one is discarded, so the
    /// cell keeps its current scene.
    public mutating func integrate(
        coordinate: CellCoordinate,
        kind: BuildKind
    ) -> IntegrationResult {
        guard inFlight.remove(coordinate) != nil else {
            let wasRebuilding = rebuilding.remove(coordinate) != nil
            return wasRebuilding && kind == .success ? .integrated : .discardedStale
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
