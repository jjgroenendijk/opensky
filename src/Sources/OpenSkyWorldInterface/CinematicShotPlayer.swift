import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import simd

nonisolated public struct CinematicCameraPose: Equatable, Sendable {
    public var eye: SIMD3<Float>
    public var lookAt: SIMD3<Float>
    /// False for a map view, which looks down through terrain and roofs on
    /// purpose. A shot near the ground pulls its eye in front of geometry.
    public var avoidsGeometry: Bool
    /// The camera mesh's animated horizontal view, radians; nil keeps the game's.
    public var horizontalFieldOfView: Float?

    public init(
        eye: SIMD3<Float>, lookAt: SIMD3<Float>, avoidsGeometry: Bool = true,
        horizontalFieldOfView: Float? = nil
    ) {
        self.eye = eye
        self.lookAt = lookAt
        self.avoidsGeometry = avoidsGeometry
        self.horizontalFieldOfView = horizontalFieldOfView
    }
}
