// Per-frame audio tick (milestone 9.1.3): pushes the live listener pose into
// the world audio engine and runs source housekeeping. Same subsystem shape as
// updateWeatherFromWallClock/updateParticles — called from draw(in:) on the
// main thread, gated on worldSimPaused through its own FrameSimClock so menu
// mode freezes the tick without a time jump on resume.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyTerrain
import simd

extension GameSession {
    /// Advances the audio clock and ticks the engine. A paused frame advances
    /// the clock mark but skips the tick entirely: sources hold their state and
    /// the listener pose stays where it was when the pause began.
    public func updateAudioFromWallClock() {
        updateSoundMix(now: renderer.wallClock.now)
        let delta = audioClock.advance(to: renderer.wallClock.now, paused: worldSimPaused)
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
        let started = Stopwatch()
        // Registered first, so it runs last and covers the music tick below.
        defer {
            lastAudioUpdateMS =
                started.milliseconds
        }
        // Music runs after the engine tick so the director sees this frame's
        // retirements: a track that reached its end is already gone from
        // `sources`, which is how the playlist knows to advance.
        defer { musicDirector?.tick(deltaTime: deltaTime) }
        defer { soundDirector?.tickAmbience(deltaTime: deltaTime) }
        defer {
            soundDirector?.updateActorLoops(
                actorSoundSources?() ?? [], listener: freeFlyCamera.position
            )
        }
        defer { routeFootstepEvents() }
        worldAudio.updateListener(
            worldPosition: freeFlyCamera.position,
            yaw: freeFlyCamera.yaw,
            pitch: freeFlyCamera.pitch
        )
        worldAudio.tick(
            listenerCell: CellGridManager.cellCoordinate(for: freeFlyCamera.position),
            deltaTime: deltaTime,
            purgeRadius: loadedGridRadius + 1
        )
    }

    /// Steps the sound mix on the wall clock, so a menu's fade runs while the world is paused.
    func updateSoundMix(now: Double) {
        let seconds = soundMixWallTime.map { Float(max(now - $0, 0)) } ?? 0
        soundMixWallTime = now
        guard let worldAudio else { return }
        var inputs = soundMixInputs?() ?? SoundMixInputs()
        inputs.submerged = breath.isSubmerged
        worldAudio.advanceSoundMix(inputs, seconds: seconds)
        let levels = worldSimPaused ? .silent : soundDirector?.playback.rumbleLevels() ?? .silent
        soundRumble?(levels)
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
