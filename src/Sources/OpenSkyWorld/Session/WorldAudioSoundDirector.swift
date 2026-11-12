// World SFX and ambience. One-shots play on use-key events, routed through SNDR.GNAM to
// the SNCT chain. The region sounds change with the center cell, through their category's
// submix (WorldAudioSoundDirector+Region.swift). A missing engine, store or file means
// silence, not a crash. Papyrus subscribes to the same `onInteraction` seam beside this.

public import Foundation
public import OpenSkyAudio
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyWorldInterface
import simd

@MainActor
public final class WorldAudioSoundDirector {
    static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "WorldAudioDirector"
    )

    let engine: WorldAudioEngine
    let soundStore: SoundRecordStore?
    let weatherStore: WeatherStore?
    private let aspcStore: AcousticSpaceStore?
    /// Sound files by canonical path, loaded off the main actor in production.
    let assets: AudioAssetLoader
    /// Bumped on each bed change, so a bed file that arrives late for an old bed is dropped.
    var ambienceGeneration = 0
    /// Which region loops play and when a one-shot rolls; also picks each sound's file.
    var regionSounds = RegionSoundScheduler()
    /// Source ids of the region loops that play, by sound.
    var ambienceLoopSources: [FormID: Int] = [:]
    /// Source ids of the region one-shots that may still play.
    var ambienceOneShotSources: [Int] = []
    /// The weather the region sounds follow; no weather lets every entry play.
    var currentWeather: () -> Weather.Precipitation = { .none }
    /// Whether a sound's CTDA conditions pass for the player. Unwired, they pass.
    var soundConditionsPass: ([Condition]) -> Bool = { _ in true }
    /// The request each interaction loop is for. A loop that arrives after its door
    /// closed finds another token, or none, and does not start.
    var interactionLoopTokens: [FormID: Int] = [:]
    var nextLoopToken = 0
    /// Animation loops by source and descriptor, like the interaction loops above.
    var animationLoopTokens: [AnimationSoundKey: Int] = [:]
    var animationLoopSourceIDs: [AnimationSoundKey: Int] = [:]
    /// The creature breath and movement loops that play, with where they play.
    public internal(set) var actorLoops: [ActorLoop: SIMD3<Float>] = [:]
    /// Lowercased SNDR editor ID -> FormID, built on the first animation sound.
    var soundIDsByEditorID: [String: FormID]?
    /// The sounds scripts play, by their Papyrus instance ID.
    var scriptSounds = ScriptSoundInstances()
    /// Script sounds whose file failed to load since the last retire.
    var failedScriptSounds: Set<Int32> = []

    /// SFX on use-key activation. Off by default until the user enables audio;
    /// the control writes back here.
    public var sfxEnabled = true
    /// The rumble send of each playing source whose output model allows rumble.
    var rumbleSends: [Int: SoundDescriptor.RumbleSend] = [:]
    /// Continuous ambience bed. Same default policy as `sfxEnabled`. Toggling
    /// it takes effect immediately: switching off retires the playing bed,
    /// switching back on restarts the bed the last context resolved.
    public var ambienceEnabled = true {
        didSet {
            guard ambienceEnabled != oldValue else { return }
            applyAmbienceState()
        }
    }

    /// Bed the last context resolved to, whether or not it is playing. Diffed
    /// against a fresh context to skip no-op restarts, and re-used as the bed
    /// to start when ambience is switched back on.
    var desiredBed = AmbienceBed.empty
    /// Authored motion loops by placed reference. A close or cancelled
    /// animation boundary retires exactly its loop without touching ambience
    /// or unrelated effects.
    var interactionLoopSourceIDs: [FormID: Int] = [:]

    /// Most recent SFX outcome, surfaced through the audio readout.
    var lastSFXDescription: String?
    public internal(set) var lastSFXError: String?
    /// Resolves an SNDR's raw `ONAM` link; nil leaves the channel-count rule in charge.
    public let outputModels: ((FormID) -> OutputModelProfile?)?
    /// Resolves an ASPC's raw `BNAM` link to its `REVB` record.
    public let reverbs: ((FormID) -> ReverbParameters?)?
    /// The reverb the current acoustic space asked for.
    private(set) var currentReverb = ReverbSetting.off

    init(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?,
        assets: AudioAssetLoader,
        effectRecords: EffectRecordStore? = nil
    ) {
        self.engine = engine
        self.soundStore = soundStore
        self.weatherStore = weatherStore
        self.aspcStore = aspcStore
        self.assets = assets
        outputModels = effectRecords.map(Self.outputModels(_:))
        reverbs = effectRecords.map(Self.reverbs(_:))
    }

    /// Test seam: same shape as the production init but takes a file loader
    /// closure directly so tests do not need a real VirtualFileSystem.
    public init(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?,
        fileLoader: @escaping (String) throws -> Data
    ) {
        self.engine = engine
        self.soundStore = soundStore
        self.weatherStore = weatherStore
        self.aspcStore = aspcStore
        assets = AudioAssetLoader(immediate: fileLoader)
        outputModels = nil
        reverbs = nil
    }

    var playback: WorldAudioPlayback {
        WorldAudioPlayback(director: self)
    }

    var interactionSounds: WorldAudioInteractionSounds {
        WorldAudioInteractionSounds(director: self)
    }

    public func handleInteraction(_ event: InteractionEvent) {
        interactionSounds.handleInteraction(event)
    }

    public func handleInteractionAnimation(_ event: InteractionAnimationEvent) {
        interactionSounds.handleInteractionAnimation(event)
    }

    // MARK: - Streamer event hooks

    /// CellStreamer.onAmbienceContextChanged subscriber. Resolves the new bed
    /// and, when it differs from the last resolved one, retires the previous
    /// sources and starts the new ones. A bed that did not change is a no-op;
    /// a bed resolved while ambience is off is remembered but not started.
    public func handleAmbienceContext(_ context: AmbienceContext) {
        let bed = AmbienceBed.resolve(
            context: context,
            weatherStore: weatherStore,
            aspcStore: aspcStore
        )
        applyReverb(context)
        guard bed != desiredBed else { return }
        desiredBed = bed
        applyAmbienceState()
    }

    /// The acoustic space's reverb, or off outdoors and in a space without one.
    private func applyReverb(_ context: AmbienceContext) {
        let reverb = context.acousticSpace
            .flatMap { aspcStore?.acousticSpace($0)?.reverbModel }
            .flatMap { reverbs?($0) }
        let setting = ReverbSetting(record: reverb)
        guard setting != currentReverb else { return }
        currentReverb = setting
        engine.applyReverb(setting)
    }

    // MARK: - Readout entry points (Phase 3 verification surface)

    /// Forces a one-shot SFX for any resolved SNDR FormID. Used by the World >
    /// Audio readout to verify SFX without relying on a walk-mode interaction.
    public func forcePlaySound(formID: FormID, position: SIMD3<Float>) {
        guard engine.isRunning else {
            lastSFXError = "engine not running"
            return
        }
        playback.playResolved(id: formID, at: position, kind: "SFX")
    }
}

/// Starting a sound: resolving its descriptor, loading its file, and routing it.
struct WorldAudioPlayback {
    let director: WorldAudioSoundDirector
}

/// Door and activator sounds: the activation one-shot and a door animation's sounds.
struct WorldAudioInteractionSounds {
    let director: WorldAudioSoundDirector
}
