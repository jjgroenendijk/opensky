// The actor the camera comes too close to fades out, as in the game, so the view never
// shows the inside of a body (docs/engine/actor-camera-fade.md).

public import OpenSkyRenderCore
import simd

extension Renderer {
    /// This frame's fade of each actor near the camera, by its reference.
    public var actorCameraFadeOuts: [UInt32: Float] {
        fadeTimers.actorCamera.fadeOuts
    }

    /// How much the view centre counts in a "Use Target" depth of field focus.
    public var depthOfFieldFocus: DepthOfFieldFocus {
        fadeTimers.depthOfFieldFocus
    }

    /// Steps the timers that follow the view: the actor camera fade and the centre weight
    /// of the depth of field focus.
    func advanceViewTimers(seconds: Float) {
        let view = frameInput.view
        fadeTimers.actorCamera.advance(scene: frameInput.actorCameraScene, seconds: seconds)
        fadeTimers.depthOfFieldFocus.advance(
            angles: SIMD3(view.pitch, 0, view.yaw), position: view.position,
            interior: activeLighting != nil, seconds: seconds
        )
    }
}
