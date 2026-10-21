// The simulation side of a frame, as the renderer sees it. Live frame:
// `prepareLiveFrame` (camera, frame steps, clock, world, weather) returns the
// frame's input, then the renderer's own step, then `finishLiveFrame` (audio).
// An offscreen frame does the same on a fixed step.

import Metal

@MainActor
public protocol RenderFrameDriver: AnyObject {
    func prepareLiveFrame() -> RenderFrameInput
    func finishLiveFrame()
    /// Steps the world by `deltaTime` (zero while paused) when `advancesWorld`, then
    /// resolves the weather, and returns the frame's input. The game clock never advances.
    func prepareOffscreenFrame(deltaTime: Float, advancesWorld: Bool) -> RenderFrameInput
    func finishOffscreenFrame(deltaTime: Float)
    /// Runs after `setScene` replaced the framing camera, so the player can be
    /// placed in the new scene.
    func didReplaceCamera(_ camera: SceneCamera)

    /// CPU wall time of the last world-simulation and audio updates.
    var lastScriptUpdateMS: Double { get }
    var lastAudioUpdateMS: Double { get }
}

/// A rig the renderer draws outside the scene, because it survives scene swaps:
/// the player's body and first-person arms.
@MainActor
public protocol RenderRig: AnyObject {
    var render: RenderScene { get }
    /// Publishes the rig's current pose to its palettes. Returns the number of
    /// bones updated.
    func publishAnimation(enabled: Bool) -> Int
}

extension Renderer {
    /// Replaces the frame's input, at the one point in the frame where game state
    /// enters the renderer. A changed field of view re-projects; changed poses re-merge.
    func adoptFrameInput(_ input: RenderFrameInput) {
        var input = input
        if let horizontal = input.horizontalFOVRadians, horizontal > 0, drawableAspectRatio > 0 {
            input.fovYRadians = 2 * atan(tan(horizontal / 2) / drawableAspectRatio)
        }
        frameInput = input
        if input.fovYRadians != adoptedFOVYRadians {
            adoptedFOVYRadians = input.fovYRadians
            rebuildProjection()
        }
        if input.instancePoses.revision != adoptedPoseRevision {
            adoptedPoseRevision = input.instancePoses.revision
            mergeInstanceDeltas()
        }
        if let tuning = input.precipitationTuning, tuning != precipitation.tuning {
            precipitation.tuning = tuning
        }
        prepareClouds()
    }
}
