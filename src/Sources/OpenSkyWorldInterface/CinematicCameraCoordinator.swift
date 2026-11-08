import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

/// One frame's override pose, shake, and world time scale, which the app writes.
nonisolated public struct CinematicFrame: Equatable, Sendable {
    /// Nil while no shot plays, so the player's own view shows.
    public let pose: CinematicCameraPose?
    public let shake: SIMD3<Float>
    public let timeScale: Float

    public init(pose: CinematicCameraPose?, shake: SIMD3<Float>, timeScale: Float) {
        self.pose = pose
        self.shake = shake
        self.timeScale = timeScale
    }
}
