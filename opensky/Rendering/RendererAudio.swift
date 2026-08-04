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
        guard !worldSimPaused else {
            // A paused frame does no audio work at all, so the measured cost of
            // this frame's audio update is genuinely zero rather than the stale
            // value from the last unpaused frame.
            lastAudioUpdateMS = 0
            return
        }
        updateAudio(deltaTime: delta)
    }

    /// Pushes the camera pose as the listener, advances in-flight gain ramps by
    /// `deltaTime` seconds, and retires finished or streamed-away sources.
    /// AVFAudio advances playback itself on its own render thread; `deltaTime`
    /// drives only the engine-side fades, which is why a paused frame (which
    /// never reaches here) freezes a crossfade instead of skipping through it.
    ///
    /// The whole update is timed into `lastAudioUpdateMS`, which the offscreen
    /// benchmark samples per frame the same way it samples the animation and
    /// shadow updates. With no engine attached the guard below returns before
    /// the clock is read, so the instrumentation costs one optional test.
    func updateAudio(deltaTime: Float) {
        guard let worldAudio else {
            lastAudioUpdateMS = 0
            return
        }
        let started = DispatchTime.now().uptimeNanoseconds
        // Registered first, so it runs last and covers the music tick below.
        defer {
            lastAudioUpdateMS =
                Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        }
        // Music runs after the engine tick so the director sees this frame's
        // retirements: a track that reached its end is already gone from
        // `sources`, which is how the playlist knows to advance.
        defer { musicDirector?.tick(deltaTime: deltaTime) }
        defer { routeFootstepEvents() }
        worldAudio.updateListener(
            worldPosition: freeFlyCamera.position,
            yaw: freeFlyCamera.yaw,
            pitch: freeFlyCamera.pitch
        )
        worldAudio.tick(
            listenerCell: CellGridManager.cellCoordinate(for: freeFlyCamera.position),
            deltaTime: deltaTime
        )
    }

    /// Drains the locomotion bridge's fired graph events into the footstep
    /// director (issue #352).
    ///
    /// Draining unconditionally — even with no director and outside walk
    /// mode — is deliberate: the queue must not accumulate events from a mode
    /// where nothing is listening and then flush them all at once the moment
    /// audio is switched on. Footsteps are heard at the capsule's feet rather
    /// than at the listener, which is what makes third person sound right.
    private func routeFootstepEvents() {
        let events = locomotion.graphEvents.drain()
        guard movementMode.isPlayerControlled else { return }
        footstepDirector?.handleGraphEvents(
            events,
            gait: locomotion.status.gait,
            position: walkController.feetPosition
        )
    }
}
