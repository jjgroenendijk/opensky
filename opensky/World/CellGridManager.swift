// Streaming grid manager (todo 3.2 grid manager): camera position -> desired
// NxN exterior-cell grid, diffed against whatever the caller currently has
// loaded. Pure math — no AppKit/Metal, no I/O, no async — so the mapping,
// grid contents, diffing and hysteresis are all unit-testable in isolation
// from the async build/streaming controller that will drive this on later
// commits of this branch. See docs/engine/cell-streaming.md.

import simd

/// Integer exterior-cell coordinate for grid streaming. Distinct from
/// `Cell.Grid` (the decoded XCLC record field, which also carries the
/// force-hide-land-quad flags and belongs to one parsed plugin) — this is
/// the pure streaming-side type. `CellSceneBuilder.buildScene` still takes
/// raw `gridX`/`gridY` Int32; convert at the call site (`coordinate.x`,
/// `coordinate.y`).
nonisolated struct CellCoordinate: Hashable {
    var x: Int32
    var y: Int32
}

/// Cells to load and cells to unload, computed fresh each call against
/// whatever the caller reports as currently resident (`CellGridManager`
/// tracks no loaded state of its own — see that type's doc comment). Both
/// sets empty never surfaces: `CellGridManager.update` returns nil instead.
nonisolated struct CellGridDiff: Equatable {
    let loads: Set<CellCoordinate>
    let unloads: Set<CellCoordinate>
}

/// Camera position -> desired streaming grid, with hysteresis against
/// border thrash. Value type, `simd`-only — safe to construct, mutate and
/// test without a renderer or file I/O.
///
/// Ownership split (the design this type settles on): `CellGridManager`
/// tracks only its own desired *center* cell, not the set of cells actually
/// loaded. The loaded set stays entirely with the caller (the async
/// streaming controller landing in a later commit on this branch), because
/// that caller's loads are async and can finish out of order or fail
/// outright — if the manager guessed at completion it would drift from
/// reality. Instead `update(cameraPosition:loaded:)` takes the caller's
/// current loaded set as an argument every frame and returns a fresh diff
/// against it; a load that failed or is still in flight simply reappears in
/// `loads` on the next call. No separate confirm/cancel/retry API needed —
/// the loaded set the caller passes in next frame is the only state that
/// matters.
nonisolated struct CellGridManager {
    /// uGridsToLoad default = 5 (full grid side length, always odd) -> 2
    /// rings around the center cell. Ref: UESP "Skyrim:INI Settings" (Grid
    /// section, `uGridsToLoad`); community SKSE/CK docs describe the same
    /// odd-side-length, center-plus-N-rings convention.
    static let defaultRadius: Int32 = 2

    /// Camera must sit at least this far inside a newly-crossed cell border
    /// before the grid re-centers. Rationale: floor-division alone
    /// re-centers on every crossing of the exact 4096-unit boundary, so a
    /// camera drifting back and forth across one border (patrol path, mouse
    /// jitter, floating-point noise right at the line) thrashes load/unload
    /// every frame. 128 units (~1.8 m, docs/decisions/coordinates.md scale)
    /// is small next to the 4096-unit cell -- negligible for "which cell is
    /// this really" purposes -- but comfortably larger than positional
    /// noise, so a border crossed once decisively still re-centers on the
    /// very next `update`.
    static let hysteresisMargin: Float = 128

    /// One exterior cell edge, world units. Shares `TerrainMeshBuilder`'s
    /// constant (docs/decisions/coordinates.md) instead of redefining it.
    private static let cellSize = TerrainMeshBuilder.cellSize

    /// Rings around center; 0 = just the center cell, `defaultRadius` = 5x5.
    let radius: Int32

    /// Current desired grid center. Only this type's own recenter
    /// hysteresis mutates it — never set directly by the caller.
    private(set) var center: CellCoordinate

    /// - Parameters:
    ///   - initialPosition: camera world position at construction; seeds
    ///     `center` directly, no hysteresis on the first frame.
    ///   - radius: rings around center; negative values clamp to 0.
    init(initialPosition: SIMD3<Float>, radius: Int32 = CellGridManager.defaultRadius) {
        self.radius = Swift.max(0, radius)
        center = Self.cellCoordinate(for: initialPosition)
    }

    /// Maps a world position to its exterior cell coordinate by floor
    /// division, never truncation -- a camera at X=-1 belongs to cell -1,
    /// not cell 0 (docs/decisions/coordinates.md: cell (x,y) covers world
    /// X in [x*4096, (x+1)*4096), same for Y).
    static func cellCoordinate(for position: SIMD3<Float>) -> CellCoordinate {
        CellCoordinate(
            x: Int32((position.x / cellSize).rounded(.down)),
            y: Int32((position.y / cellSize).rounded(.down))
        )
    }

    /// The full (2*radius+1)^2 square of cells wanted around `center`.
    /// Unordered — a Set, since load ordering/priority is the streaming
    /// controller's concern, not this type's.
    var desiredCells: Set<CellCoordinate> {
        let side = Int(2 * radius + 1)
        var cells: Set<CellCoordinate> = []
        cells.reserveCapacity(side * side)
        for offsetX in -radius ... radius {
            for offsetY in -radius ... radius {
                cells.insert(CellCoordinate(x: center.x + offsetX, y: center.y + offsetY))
            }
        }
        return cells
    }

    /// Advances the grid for one frame's camera position, then diffs the
    /// desired grid against `loaded` (whatever the caller currently has
    /// resident). Returns nil when there is nothing to do: center held
    /// (hysteresis) or moved but `loaded` already matches the new desired
    /// grid exactly.
    mutating func update(
        cameraPosition: SIMD3<Float>,
        loaded: Set<CellCoordinate>
    ) -> CellGridDiff? {
        recenterIfNeeded(cameraPosition: cameraPosition)
        let desired = desiredCells
        let loads = desired.subtracting(loaded)
        let unloads = loaded.subtracting(desired)
        guard !loads.isEmpty || !unloads.isEmpty else { return nil }
        return CellGridDiff(loads: loads, unloads: unloads)
    }

    /// Re-centers on the camera's current cell, but only once the camera
    /// has penetrated `hysteresisMargin` past whichever border it just
    /// crossed, checked per axis (so a diagonal corner crossing needs
    /// margin clearance on both axes). An axis that did not change cell
    /// needs no clearance on that axis.
    private mutating func recenterIfNeeded(cameraPosition position: SIMD3<Float>) {
        let candidate = Self.cellCoordinate(for: position)
        guard candidate != center else { return }

        let localX = position.x - Float(candidate.x) * Self.cellSize
        let localY = position.y - Float(candidate.y) * Self.cellSize

        if candidate.x != center.x {
            let depth = candidate.x > center.x ? localX : Self.cellSize - localX
            guard depth >= Self.hysteresisMargin else { return }
        }
        if candidate.y != center.y {
            let depth = candidate.y > center.y ? localY : Self.cellSize - localY
            guard depth >= Self.hysteresisMargin else { return }
        }
        center = candidate
    }
}
