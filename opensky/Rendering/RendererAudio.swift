// Per-frame audio tick (milestone 9.1.3): pushes the live listener pose into
// the world audio engine and runs source housekeeping. Same subsystem shape as
// updateWeatherFromWallClock/updateParticles — called from draw(in:) on the
// main thread, gated on worldSimPaused through its own FrameSimClock so menu
// mode freezes the tick without a time jump on resume.

import QuartzCore
import simd

extension Renderer {
    /// Advances the audio clock and ticks the engine. A paused frame advances
    /// the clock mark but skips the tick entirely: sources hold their state and
    /// the listener pose stays where it was when the pause began.
    func updateAudioFromWallClock() {
        let delta = audioClock.advance(to: CACurrentMediaTime(), paused: worldSimPaused)
        guard !worldSimPaused else { return }
        updateAudio(deltaTime: delta)
    }

    /// Pushes the camera pose as the listener and retires finished or
    /// streamed-away sources. `deltaTime` is accepted for parity with the other
    /// subsystem ticks; the engine currently needs only the pose and the tick
    /// itself (AVFAudio advances playback on its own render thread).
    func updateAudio(deltaTime _: Float) {
        guard let worldAudio else { return }
        worldAudio.updateListener(
            worldPosition: freeFlyCamera.position,
            yaw: freeFlyCamera.yaw,
            pitch: freeFlyCamera.pitch
        )
        worldAudio.tick(
            listenerCell: CellGridManager.cellCoordinate(for: freeFlyCamera.position)
        )
    }
}
