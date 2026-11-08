public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `CinematicCameraCoordinator`.
public protocol CinematicCameraPort: AnyObject {
    var isPlaying: Bool { get }
    @discardableResult func playKillCam(
        attacker: ReferenceKey,
        target: ReferenceKey,
        remainingHostiles: Int,
        force: Bool
    ) -> Bool
    @discardableResult func startShake(source: SIMD3<Float>?, strength: Float, duration: Float)
        -> Bool
    func tick(realSeconds: Double) -> CinematicFrame
}

/// The default arguments a protocol requirement cannot carry.
extension CinematicCameraPort {
    @discardableResult public func playKillCam(
        attacker: ReferenceKey,
        target: ReferenceKey,
        remainingHostiles: Int
    ) -> Bool {
        playKillCam(
            attacker: attacker,
            target: target,
            remainingHostiles: remainingHostiles,
            force: false
        )
    }
}
