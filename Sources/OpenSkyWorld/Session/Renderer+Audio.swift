// Per-frame audio tick (milestone 9.1.3): pushes the live listener pose into
// the world audio engine and runs source housekeeping. Same subsystem shape as
// updateWeatherFromWallClock/updateParticles — called from draw(in:) on the
// main thread, gated on worldSimPaused through its own FrameSimClock so menu
// mode freezes the tick without a time jump on resume.

import Foundation
import OpenSkyAudio
import OpenSkyRendering
import simd

extension Renderer {
    /// Advances the audio clock and ticks the engine. A paused frame advances
    /// the clock mark but skips the tick entirely: sources hold their state and
    /// the listener pose stays where it was when the pause began.
    public func updateAudioFromWallClock() {
        let delta = audioClock.advance(to: wallClock.now, paused: worldSimPaused)
        guard !worldSimPaused else {
            // A paused frame does no audio work at all, so the measured cost of
            // this frame's audio update is genuinely zero rather than the stale
            // value from the last unpaused frame.
            lastAudioUpdateMS = 0
            return
        }
        updateAudio(deltaTime: delta)
    }

    /// Pushes the listener pose, advances gain ramps by `deltaTime` and retires finished
    /// sources. A paused frame never gets here, so a crossfade freezes. Timed into
    /// `lastAudioUpdateMS` for the offscreen benchmark.
    public func updateAudio(deltaTime: Float) {
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

    /// Drains the bridge's graph events into the footstep director. Always drains, so no
    /// backlog plays at once when audio turns on. Steps sound at the capsule's feet.
    private func routeFootstepEvents() {
        let events = locomotion.graphEvents.drain(locomotion.footstepEventConsumer)
        guard movementMode.isPlayerControlled else { return }
        footstepDirector?.handleGraphEvents(
            events,
            gait: locomotion.status.gait,
            position: walkController.feetPosition,
            material: walkController.groundMaterial
        )
    }
}
