// World SFX and ambience. One-shots play on use-key events, routed through SNDR.GNAM to
// the SNCT chain. The region sounds change with the center cell, through their category's
// submix (WorldAudioSoundDirector+Region.swift). A missing engine, store or file means
// silence, not a crash. Papyrus subscribes to the same `onInteraction` seam beside this.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import simd

private struct ResolvedSoundFile {
    let path: String
    let category: AudioCategory
    let outputModel: FormID?
}

/// One sound waiting for its file: where it plays, and whether it is still wanted.
private struct PendingSound {
    let resolved: ResolvedSoundFile
    /// Nil plays the sound without a position, as region sounds do.
    let position: SIMD3<Float>?
    let kind: String
    let loops: Bool
    let adopt: ((Int) -> Bool)?
}

@MainActor
public final class WorldAudioSoundDirector {
    public static let logger = EngineLogger(
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
    public var currentWeather: () -> Weather.Precipitation = { .none }
    /// Whether a sound's CTDA conditions pass for the player. Unwired, they pass.
    public var soundConditionsPass: ([Condition]) -> Bool = { _ in true }
    /// The request each interaction loop is for. A loop that arrives after its door
    /// closed finds another token, or none, and does not start.
    private var interactionLoopTokens: [FormID: Int] = [:]
    private var nextLoopToken = 0

    /// SFX on use-key activation. Off by default until the user enables audio;
    /// the panel control writes back here.
    public var sfxEnabled = true
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
    private var interactionLoopSourceIDs: [FormID: Int] = [:]

    /// Most recent SFX outcome, surfaced through the World > Audio readout.
    public private(set) var lastSFXDescription: String?
    public private(set) var lastSFXError: String?
    /// The routing the last one-shot took, and why, for the readout.
    public private(set) var lastRouting: String?
    /// Resolves an SNDR's raw `ONAM` link; nil leaves the channel-count rule in charge.
    public var outputModels: ((FormID) -> OutputModelProfile?)?
    /// Resolves an ASPC's raw `BNAM` link to its `REVB` record.
    public var reverbs: ((FormID) -> ReverbParameters?)?
    /// The reverb the current acoustic space asked for.
    public private(set) var currentReverb = ReverbSetting.off
    /// The `REVB` record behind `currentReverb`, nil outdoors.
    public private(set) var currentReverbRecord: ReverbParameters?

    public init(
        engine: WorldAudioEngine,
        soundStore: SoundRecordStore?,
        weatherStore: WeatherStore?,
        aspcStore: AcousticSpaceStore?,
        assets: AudioAssetLoader
    ) {
        self.engine = engine
        self.soundStore = soundStore
        self.weatherStore = weatherStore
        self.aspcStore = aspcStore
        self.assets = assets
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
    }

    // MARK: - Streamer event hooks

    /// CellStreamer.onInteraction subscriber. Plays the activator's activation
    /// sound (DOOR.SNAM, ACTI.VNAM, CONT.SNAM) at the placed position.
    public func handleInteraction(_ event: InteractionEvent) {
        guard sfxEnabled, engine.isRunning else { return }
        guard
            let sounds = event.target.interaction.sounds,
            let activationID = sounds.activation
        else { return }
        playResolved(
            id: activationID,
            at: event.target.interaction.position,
            kind: "SFX"
        )
    }

    /// Door-animation lifecycle subscriber. Movement starts the authored loop;
    /// close and cancellation both retire it, while only close plays the
    /// authored one-shot. The same event also supports a future container
    /// animation because DOOR.ANAM and CONT.QNAM share `sounds.close`.
    public func handleInteractionAnimation(_ event: InteractionAnimationEvent) {
        let interaction = event.interaction
        switch event.phase {
        case .motionStarted:
            retireInteractionLoop(reference: interaction.reference)
            guard
                sfxEnabled,
                engine.isRunning,
                let loopID = interaction.sounds?.loop
            else { return }
            nextLoopToken += 1
            let token = nextLoopToken
            let reference = interaction.reference
            interactionLoopTokens[reference] = token
            playResolved(
                id: loopID, at: interaction.position, kind: "interaction loop", loops: true
            ) { [weak self] sourceID in
                guard let self, interactionLoopTokens[reference] == token else { return false }
                interactionLoopSourceIDs[reference] = sourceID
                return true
            }
        case .closed:
            retireInteractionLoop(reference: interaction.reference)
            guard
                sfxEnabled,
                engine.isRunning,
                let closeID = interaction.sounds?.close
            else { return }
            playResolved(
                id: closeID,
                at: interaction.position,
                kind: "interaction close"
            )
        case .cancelled:
            retireInteractionLoop(reference: interaction.reference)
        }
    }

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
        currentReverbRecord = reverb
        guard setting != currentReverb else { return }
        currentReverb = setting
        engine.applyReverb(setting)
    }

    // MARK: - Panel entry points (Phase 3 verification surface)

    /// Forces a one-shot SFX for any resolved SNDR FormID. Used by the World >
    /// Audio panel to verify SFX without relying on a walk-mode interaction.
    public func forcePlaySound(formID: FormID, position: SIMD3<Float>) {
        guard engine.isRunning else {
            lastSFXError = "engine not running"
            return
        }
        playResolved(id: formID, at: position, kind: "SFX")
    }

    // MARK: - Internals

    /// Starts the sound when its file is loaded. `adopt` gets the new source's id and
    /// returns false for a sound no longer wanted, which then stops at once.
    func playResolved(
        id: FormID,
        at position: SIMD3<Float>?,
        kind: String,
        loops: Bool = false,
        adopt: ((Int) -> Bool)? = nil
    ) {
        guard let resolved = resolveSound(id: id) else {
            lastSFXError = "unresolved \(id.description)"
            Self.logger.debug(
                "[INFO] \(kind, privacy: .public) unresolved: \(id.description, privacy: .public)"
            )
            return
        }
        let pending = PendingSound(
            resolved: resolved, position: position, kind: kind, loops: loops, adopt: adopt
        )
        assets.request(resolved.path) { [weak self] result in
            self?.start(result, pending)
        }
    }

    private func retireInteractionLoop(reference: FormID) {
        interactionLoopTokens[reference] = nil
        guard let sourceID = interactionLoopSourceIDs.removeValue(forKey: reference) else {
            return
        }
        engine.stopSource(id: sourceID)
    }
}

/// Starting a sound once its file arrives.
extension WorldAudioSoundDirector {
    private func start(
        _ result: Result<AudioFileAsset, AssetLoadFailure>,
        _ pending: PendingSound
    ) {
        let resolved = pending.resolved
        do {
            let asset = try result.get()
            let profile = resolved.outputModel.flatMap { outputModels?($0) }
            var request = AudioPlayRequest(
                name: resolved.path,
                category: resolved.category,
                worldPosition: pending.position ?? .zero,
                loops: pending.loops
            )
            request.outputModel = profile
            let routing = pending.position == nil ? .nonPositional : AudioRoutingDecision.routing(
                profile: profile,
                channelCount: profile == nil ? asset.channelCount : nil
            )
            lastRouting = "\(routing.rawValue) (\(profile?.name ?? "channel count"))"
            let sourceID = try routing == .positional
                ? engine.playPositional(asset: asset, request: request)
                : engine.playNonPositional(asset: asset, request: request)
            if let adopt = pending.adopt, !adopt(sourceID) {
                engine.stopSource(id: sourceID)
                return
            }
            lastSFXDescription = resolved.path
            lastSFXError = nil
        } catch {
            let reason = String(describing: error)
            lastSFXError = reason
            let kind = pending.kind
            Self.logger.warning(
                "[WARNING] \(kind, privacy: .public) play failed: \(reason, privacy: .public)"
            )
        }
    }

    /// A descriptor with several files plays one of them at random, as the game does.
    private func resolveSound(id: FormID) -> ResolvedSoundFile? {
        guard let soundStore else { return nil }
        let resolved: ResolvedSound
        do {
            resolved = try soundStore.resolveAny(id)
        } catch {
            return nil
        }
        guard !resolved.filePaths.isEmpty else { return nil }
        let path = resolved.filePaths[regionSounds.pick(count: resolved.filePaths.count)]
        return ResolvedSoundFile(
            path: path,
            category: resolved.audioCategory ?? .effects,
            outputModel: resolved.descriptor.outputModel
        )
    }
}
