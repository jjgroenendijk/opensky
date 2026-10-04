// The local map's top-down view and its fog squares. An exterior view covers the
// loaded grid around the player; an interior view covers the cell's bounds. The
// size is an OpenSky choice: the install sets no [MapMenu] values.
// See docs/engine/world-map.md, local map.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyWorldInterface
import simd

nonisolated public struct LocalMapView: Equatable, Sendable {
    public static let cellSize: Float = 4096

    public let center: SIMD2<Float>
    /// Half the side of the square the map shows, in world units.
    public let halfExtent: Float

    public init(center: SIMD2<Float>, halfExtent: Float) {
        self.center = center
        self.halfExtent = max(halfExtent, 1)
    }

    /// The loaded `grid` by `grid` cells around the player's cell.
    public static func exterior(player: SIMD3<Float>, grid: Int) -> Self {
        let cell = SIMD2((player.x / cellSize).rounded(.down), (player.y / cellSize).rounded(.down))
        let center = (cell + 0.5) * cellSize
        return LocalMapView(
            center: center, halfExtent: Float(max(grid, 1)) * cellSize / 2
        )
    }

    /// A world point on the map image, 0 to 1 with y down, or nil outside it.
    public func project(_ point: SIMD3<Float>) -> SIMD2<Float>? {
        let local = (SIMD2(point.x, point.y) - center) / (halfExtent * 2) + 0.5
        guard (0 ... 1).contains(local.x), (0 ... 1).contains(local.y) else { return nil }
        return SIMD2(local.x, 1 - local.y)
    }
}

nonisolated public enum LocalMapFog {
    /// The fog square of a point: an exterior cell is split in 8 by 8; an interior
    /// uses its bounds.
    public static func square(
        of point: SIMD3<Float>, cell: CellSceneLocation, interiorBounds: (
            SIMD2<Float>,
            SIMD2<Float>
        )? = nil
    ) -> (column: Int, row: Int) {
        let side = Float(LocalMapFogState.gridSide)
        let fraction: SIMD2<Float> = switch cell {
        case let .exterior(coordinate):
            (SIMD2(point.x, point.y) - SIMD2(Float(coordinate.x), Float(coordinate.y)) *
                LocalMapView.cellSize)
                / LocalMapView.cellSize
        case .interior:
            interiorBounds.map { low, high in
                (SIMD2(point.x, point.y) - low) / simd_max(high - low, SIMD2(repeating: 1))
            } ?? SIMD2(repeating: 0.5)
        }
        let clamped = simd_clamp(fraction, SIMD2(repeating: 0), SIMD2(repeating: 0.999))
        return (Int(clamped.x * side), Int(clamped.y * side))
    }
}
