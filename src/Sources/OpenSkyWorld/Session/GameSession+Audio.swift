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

extension GameSession.AudioSteps {
    /// Advances the audio clock and ticks the engine. A paused frame advances
    /// the clock mark but skips the tick entirely: sources hold their state and
    /// the listener pose stays where it was when the pause began.
    public func updateAudioFromWallClock() {
        updateSoundMix(now: session.renderer.wallClock.now)
        let delta = session.audio.audioClock.advance(
            to: session.renderer.wallClock.now,
            paused: session.worldSimPaused
        )
        guard !session.worldSimPaused else {
            // A paused frame does no audio work at all, so the measured cost of
            // this frame's audio update is genuinely zero rather than the stale
            // value from the last unpaused frame.
            session.audio.lastAudioUpdateMS = 0
            return
        }
        updateAudio(deltaTime: delta)
    }

    /// Pushes the listener pose, advances gain ramps by `deltaTime` and retires finished
    /// sources. A paused frame never gets here, so a crossfade freezes. Timed into
    /// `lastAudioUpdateMS` for the offscreen benchmark.
    public func updateAudio(deltaTime: Float) {
        guard let worldAudio = session.audio.worldAudio else {
            session.audio.lastAudioUpdateMS = 0
            return
        }
        let started = Stopwatch()
        // Registered first, so it runs last and covers the music tick below.
        defer {
            session.audio.lastAudioUpdateMS =
                started.milliseconds
        }
        // Music runs after the engine tick so the director sees this frame's
        // retirements: a track that reached its end is already gone from
        // `sources`, which is how the playlist knows to advance.
        defer { session.audio.musicDirector?.tick(deltaTime: deltaTime) }
        defer { session.audio.soundDirector?.tickAmbience(deltaTime: deltaTime) }
        defer {
            session.audio.soundDirector?.updateActorLoops(
                session.audio.actorSoundSources?() ?? [], listener: session.freeFlyCamera.position
            )
        }
        defer { routeFootstepEvents() }
        worldAudio.updateListener(
            worldPosition: session.freeFlyCamera.position,
            yaw: session.freeFlyCamera.yaw,
            pitch: session.freeFlyCamera.pitch
        )
        worldAudio.tick(
            listenerCell: CellGridManager.cellCoordinate(for: session.freeFlyCamera.position),
            deltaTime: deltaTime,
            purgeRadius: session.loadedGridRadius + 1
        )
    }

    /// Steps the sound mix on the wall clock, so a menu's fade runs while the world is paused.
    func updateSoundMix(now: Double) {
        let seconds = session.audio.soundMixWallTime.map { Float(max(now - $0, 0)) } ?? 0
        session.audio.soundMixWallTime = now
        guard let worldAudio = session.audio.worldAudio else { return }
        var inputs = session.audio.soundMixInputs?() ?? SoundMixInputs()
        inputs.submerged = session.motion.breath.isSubmerged
        worldAudio.advanceSoundMix(inputs, seconds: seconds)
        let levels = session.worldSimPaused ? .silent : session.audio.soundDirector?.playback
            .rumbleLevels() ?? .silent
        session.audio.soundRumble?(levels)
    }

    /// Drains the bridge's graph events into the footstep director. Always drains, so no
    /// backlog plays at once when audio turns on. Steps sound at the capsule's feet.
    private func routeFootstepEvents() {
        let events = session.locomotion.graphEvents.drain(session.locomotion.footstepEventConsumer)
        guard session.movementMode.isPlayerControlled else { return }
        session.audio.footstepDirector?.handleGraphEvents(
            events,
            gait: session.locomotion.status.gait,
            position: session.walkController.feetPosition,
            material: session.walkController.groundMaterial
        )
    }
}
