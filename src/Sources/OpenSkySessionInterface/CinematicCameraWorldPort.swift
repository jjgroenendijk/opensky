public import OpenSkyFormatsESM

/// What the world adapters use of `CinematicCameraWorldAdapter`.
public protocol CinematicCameraWorldPort: AnyObject {
    func actorDied(_ key: ReferenceKey)
    func anchorPosition(of key: ReferenceKey) -> SIMD3<Float>?
}
