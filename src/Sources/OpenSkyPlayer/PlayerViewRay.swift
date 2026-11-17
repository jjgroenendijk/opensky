// The ray the crosshair picks along. See docs/engine/interaction.md, "Picking a target".

public import OpenSkyRenderCore
public import OpenSkyWorldInterface
import simd

nonisolated public enum PlayerViewRay {
    /// The pick ray for `mode`, along the view direction. First person starts at the eye.
    /// Third person starts at the orbit pivot plus the camera's sideways offset, without the
    /// zoom, so the reach counts from the player and not from the camera behind them.
    public static func make(
        mode: CameraMovementMode,
        camera: FreeFlyCamera,
        feetPosition: SIMD3<Float>,
        reach: Float = InteractionRay.defaultMaximumDistance
    ) -> InteractionRay? {
        let origin: SIMD3<Float>
        switch mode {
        case .fly:
            return nil
        case .walk:
            origin = camera.position
        case .thirdPerson:
            origin = ThirdPersonCamera.pivot(feetPosition: feetPosition)
                + camera.right * ThirdPersonCamera.shoulderOffset
        }
        return InteractionRay(origin: origin, direction: camera.forward, maximumDistance: reach)
    }
}
