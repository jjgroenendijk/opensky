// Part of the `GameSession` state, held in one object so the session port can name it.

public import OpenSkyActorPresentation
public import OpenSkyAudio
import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWeather
import OpenSkyWorldInterface
import simd

/// The world audio graph, the sound and music directors, and the sound mix inputs of a session.
public final class SessionAudio {
    /// World audio playback graph; nil until the app wires one (offscreen and
    /// CLI paths stay silent). Ticked by GameSession+Audio.swift.
    public var worldAudio: WorldAudioEngine?
    /// Region sound director, ticked from the pause-aware audio hook. Nil until audio is on.
    public var soundDirector: WorldAudioSoundDirector?
    /// The actors whose breath and movement loops may play; the app supplies them.
    public var actorSoundSources: (() -> [ActorSoundSource])?
    /// The menu, loading, and dialogue state the sound mix follows; the app supplies it.
    public var soundMixInputs: (() -> SoundMixInputs)?
    /// Takes this frame's rumble bus levels each frame, silent while the world is paused.
    public var soundRumble: ((SoundRumble) -> Void)?
    /// The wall-clock time of the last sound mix step, which also runs in menus.
    var soundMixWallTime: Double?
    /// Music director, ticked from the pause-aware audio hook. Nil until audio is on.
    public var musicDirector: WorldMusicDirector?
    /// Footstep director, fed from the pause-aware audio hook with the bridge's graph
    /// events. A paused frame fires nothing. Nil until audio is on.
    public var footstepDirector: WorldAudioFootstepDirector?
    /// Sounds, camera shake, and head tracking that clip annotations ask for. Nil until
    /// the app wires one.
    public var animationEvents: AnimationEventCoordinator?
    /// Wall-clock delta source for the audio tick, paused in menu mode.
    public var audioClock = FrameSimClock()
    /// CPU wall time of the last per-frame audio update (listener pose + engine
    /// tick + music director). Exactly zero on a frame that did no audio work,
    /// which is every frame while no `WorldAudioEngine` is attached.
    public var lastAudioUpdateMS = 0.0

    public init() {}
}
