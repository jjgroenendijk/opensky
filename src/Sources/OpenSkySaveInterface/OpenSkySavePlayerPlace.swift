import Foundation
import OpenSkyFormatsCore
public import OpenSkyGameData

/// The player's place at save time. Interior `feet` are local to its cell.
nonisolated public struct SavePlayerPlace: Equatable, Sendable {
    public let cell: CellSceneLocation
    public let feet: SIMD3<Float>
    /// Radians, the camera's yaw.
    public let yaw: Float
    /// The exterior worldspace's editor ID; nil for an interior or an older save.
    public let worldspace: String?

    public init(
        cell: CellSceneLocation, feet: SIMD3<Float>, yaw: Float, worldspace: String? = nil
    ) {
        self.cell = cell
        self.feet = feet
        self.yaw = yaw
        self.worldspace = worldspace
    }
}
