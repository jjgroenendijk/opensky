import Foundation
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyWorldState
import simd

/// Where a dropped object lands.
nonisolated public struct DropPlacement: Equatable, Sendable {
    /// Cell the object comes to rest in. The caller supplies it because only
    /// the streamer knows which cell the player is standing in.
    public let location: CellSceneLocation
    public let position: SIMD3<Float>
    public let rotation: SIMD3<Float>
    /// How far the next drop of the same dropper turns, in radians, once this one lands.
    public var fanStep: Float = 0

    public init(
        location: CellSceneLocation,
        position: SIMD3<Float>,
        rotation: SIMD3<Float> = .zero
    ) {
        self.location = location
        self.position = position
        self.rotation = rotation
    }
}
