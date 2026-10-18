// Streaming grid manager: camera position -> desired NxN exterior grid, diffed against
// what the caller has loaded. Pure math, so mapping, diffing and hysteresis are
// unit-testable. See docs/engine/cell-streaming.md.

import OpenSkyFormatsCore
import OpenSkyRendering
import simd

/// Cells to load and cells to unload, computed fresh each call against
/// whatever the caller reports as currently resident (`CellGridManager`
/// tracks no loaded state of its own — see that type's doc comment). Both
/// sets empty never surfaces: `CellGridManager.update` returns nil instead.
nonisolated public struct CellGridDiff: Equatable, Sendable {
    public let loads: Set<CellCoordinate>
    public let unloads: Set<CellCoordinate>
}

/// Camera position -> desired streaming grid, with hysteresis. It tracks only its center;
/// the caller passes the loaded set each frame and gets a fresh diff, so a failed or
/// in-flight load reappears in `loads` without a retry API.
nonisolated public struct CellGridManager: Sendable {
    /// uGridsToLoad default = 5 (full grid side length, always odd) -> 2
    /// rings around the center cell. Ref: UESP "Skyrim:INI Settings" (Grid
    /// section, `uGridsToLoad`); community SKSE/CK docs describe the same
    /// odd-side-length, center-plus-N-rings convention.
    public static let defaultRadius: Int32 = 2

    /// How far inside a crossed border the camera must be before the grid re-centers, so
    /// jitter at the line does not thrash. 128 units (about 1.8 m) is small next to a
    /// 4096-unit cell but larger than positional noise.
    public static let hysteresisMargin: Float = 128

    /// One exterior cell edge, world units. Shares `TerrainMeshBuilder`'s
    /// constant (docs/decisions/coordinates.md) instead of redefining it.
    private static let cellSize = TerrainMeshBuilder.cellSize

    /// Rings around center; 0 = just the center cell, `defaultRadius` = 5x5.
    public let radius: Int32

    /// Current desired grid center. Only this type's own recenter
    /// hysteresis mutates it — never set directly by the caller.
    public private(set) var center: CellCoordinate

    /// - Parameters:
    ///   - initialPosition: camera world position at construction; seeds
    ///     `center` directly, no hysteresis on the first frame.
    ///   - radius: rings around center; negative values clamp to 0.
    public init(initialPosition: SIMD3<Float>, radius: Int32 = CellGridManager.defaultRadius) {
        self.radius = Swift.max(0, radius)
        center = Self.cellCoordinate(for: initialPosition)
    }

    /// Maps a world position to its exterior cell coordinate by floor
    /// division, never truncation -- a camera at X=-1 belongs to cell -1,
    /// not cell 0 (docs/decisions/coordinates.md: cell (x,y) covers world
    /// X in [x*4096, (x+1)*4096), same for Y).
    public static func cellCoordinate(for position: SIMD3<Float>) -> CellCoordinate {
        CellCoordinate(
            x: Int32((position.x / cellSize).rounded(.down)),
            y: Int32((position.y / cellSize).rounded(.down))
        )
    }

    /// World position at the center of a cell (Z=0) — the inverse of
    /// `cellCoordinate(for:)` up to the half-cell offset. Seeds the grid on a
    /// known target coordinate (streaming launch centers on FirstRenderCell)
    /// so `cellCoordinate(for:)` maps it straight back to that cell.
    public static func cellCenter(of coordinate: CellCoordinate) -> SIMD3<Float> {
        SIMD3<Float>(
            (Float(coordinate.x) + 0.5) * cellSize,
            (Float(coordinate.y) + 0.5) * cellSize,
            0
        )
    }

    /// The full (2*radius+1)^2 square of cells wanted around `center`.
    /// Unordered — a Set, since load ordering/priority is the streaming
    /// controller's concern, not this type's.
    public var desiredCells: Set<CellCoordinate> {
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
    public mutating func update(
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
