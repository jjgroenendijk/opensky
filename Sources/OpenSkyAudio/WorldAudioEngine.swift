// World audio graph: positional mono players -> environment node -> main mixer, and
// one submix per menu category for music and ambience beds. Stereo is not
// spatialized, so streamers downmix. A positional source takes its category gain at
// its node. Main actor only; decoding runs on `decodeQueue`.
// See docs/engine/audio.md; sources live in WorldAudioEngineSources.swift.

import AVFAudio
import Foundation
import OpenSkyFormatsCore
import simd
import Synchronization

nonisolated public enum AudioEngineError: Error, Equatable {
    /// Playback was requested while the engine is disabled or failed to start.
    case notRunning
    /// A pcm format could not be constructed for the source's sample rate.
    case formatUnavailable
    /// The category submix a non-positional source needs is missing from the
    /// graph. Cannot happen while every `AudioCategory` gets a mixer; it exists
    /// so the play path never force-unwraps.
    case submixUnavailable
}

/// Thread-safe copy of one main-actor source clock. `LipSyncPlayback` reads it
/// during scene traversal, which is nonisolated.
nonisolated public final class VoicePlaybackClock: Sendable, Equatable {
    private let storedPosition = Mutex<Double?>(0)

    public var position: Double? {
        storedPosition.withLock { $0 }
    }

    public func publish(_ position: Double?) {
        storedPosition.withLock { $0 = position }
    }

    public static func == (lhs: VoicePlaybackClock, rhs: VoicePlaybackClock) -> Bool {
        lhs === rhs
    }
}

/// Provisional distance-attenuation defaults, in meters. Tuned only so World > Audio
/// is audibly direction- and distance-dependent until sound descriptors supply values.
nonisolated public enum ProvisionalAttenuation: Sendable {
    /// Distance at which a source plays at full gain (~2 m).
    public static let referenceDistanceMeters: Float = 2
    /// Attenuation stops growing past this distance (~one exterior cell).
    public static let maximumDistanceMeters: Float = 60
    public static let rolloffFactor: Float = 1
}

@MainActor
public final class WorldAudioEngine {
    /// Concurrent-source budget. Provisional; the eviction rule is FIFO — see
    /// `makeRoomForNewSource()` in WorldAudioEngineSources.swift.
    public static let maxConcurrentSources = 8
    /// Sources bound to a cell farther than this (Chebyshev rings) from the
    /// listener's cell are stopped on the audio tick — cleanup when the world
    /// streams away. One ring beyond the streamer's default 5x5 residency.
    public static let cellPurgeRadius: Int32 = 3

    public let engine = AVAudioEngine()
    public let environment = AVAudioEnvironmentNode()
    public private(set) var categoryMixers: [AudioCategory: AVAudioMixerNode] = [:]
    /// Serial owner of every WMADecoder and all streaming state.
    public let decodeQueue = DispatchQueue(
        label: "nl.jjgroenendijk.opensky.audio-decode",
        qos: .userInitiated
    )

    /// Playing sources, oldest first (append order = start order, which is what
    /// the FIFO eviction walks). Written only by WorldAudioEngineSources.swift;
    /// internal rather than private(set) because that file is a satellite.
    public var sources: [ActiveAudioSource] = []
    /// Next source id; taken only by WorldAudioEngineSources.swift.
    public var nextSourceID = 1
    /// Live half of the playback clock: seconds accumulated from the audio
    /// tick's paused-aware frame delta. Offline the clock reads the engine's
    /// manual-rendering sample time instead; both live in
    /// WorldAudioEngineVoice.swift, which is why this is internal.
    public var liveClockSeconds: Double = 0
    /// Called with a source's id once that source has played to its end and
    /// been retired. Set by whoever needs to know a line finished — the
    /// dialogue subtitle lifecycle and the menu's auto-advance. Never fires
    /// for a source that was stopped, evicted or purged.
    public var onSourceFinished: ((Int) -> Void)?
    /// Why the graph is not running, for the panel readout. nil while healthy.
    public private(set) var unavailableReason: String?
    /// Listener pose in world space, kept for the snapshot's distance column.
    public private(set) var listenerWorldPosition = SIMD3<Float>.zero
    /// The room reverb on the 3D submix (`WorldAudioEngineReverb.swift`).
    public var reverb = ReverbRamp()

    /// Off by default: no audio engine starts (and no output device is touched)
    /// until the user enables it in World > Audio.
    public var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                startEngine()
            } else {
                stopEngine()
            }
        }
    }

    public var isRunning: Bool {
        engine.isRunning
    }

    public var masterVolume: Float = 1 {
        didSet {
            masterVolume = simd_clamp(masterVolume, 0, 1)
            engine.mainMixerNode.outputVolume = masterVolume
            applyVolumesToSources()
        }
    }

    private var categoryVolumes: [AudioCategory: Float] =
        Dictionary(uniqueKeysWithValues: AudioCategory.allCases.map { ($0, 1) })

    /// Categories the user silenced in World > Audio. Held separately from
    /// `categoryVolumes` so unmuting restores the slider value the user had
    /// dialled in rather than snapping back to full.
    private var mutedCategories: Set<AudioCategory> = []

    /// While non-nil, only this category is audible; every other category
    /// contributes zero gain. Mute and solo are independent filters and both
    /// must pass, so soloing a category does not unmute it: an explicitly
    /// muted category stays silent even while it is the soloed one.
    public var soloedCategory: AudioCategory? {
        didSet {
            guard soloedCategory != oldValue else { return }
            applyCategoryGains()
        }
    }

    /// Offline manual-rendering hook for deterministic tests. Production passes
    /// nil and renders to the output device.
    private let manualRenderingFormat: AVAudioFormat?

    public init(manualRenderingFormat: AVAudioFormat? = nil) {
        self.manualRenderingFormat = manualRenderingFormat
        buildGraph()
    }

    public func volume(for category: AudioCategory) -> Float {
        categoryVolumes[category] ?? 1
    }

    public func setVolume(_ volume: Float, for category: AudioCategory) {
        categoryVolumes[category] = simd_clamp(volume, 0, 1)
        applyCategoryGains()
    }

    public func isMuted(_ category: AudioCategory) -> Bool {
        mutedCategories.contains(category)
    }

    /// Mutes or unmutes one category. The category's volume is untouched, so
    /// unmuting restores exactly the level the slider was left at.
    public func setMuted(_ muted: Bool, for category: AudioCategory) {
        let changed: Bool = if muted {
            mutedCategories.insert(category).inserted
        } else {
            mutedCategories.remove(category) != nil
        }
        guard changed else { return }
        applyCategoryGains()
    }

    /// The category factor the graph actually applies: the category's volume
    /// when it is audible, and zero when it is muted or when a different
    /// category is soloed. Every gain path folds mute and solo in here, so the
    /// submixes, the positional node volumes and the panel's reported
    /// `effectiveGain` can never disagree.
    public func audibleVolume(for category: AudioCategory) -> Float {
        guard !mutedCategories.contains(category) else { return 0 }
        if let soloedCategory, soloedCategory != category {
            return 0
        }
        return volume(for: category)
    }

    /// Re-applies every category factor after a volume, mute or solo change:
    /// the submixes carry it for non-positional sources, and
    /// `applyVolumesToSources()` pushes it into the positional player nodes, so
    /// already-playing sources react on the call.
    private func applyCategoryGains() {
        for category in AudioCategory.allCases {
            categoryMixers[category]?.outputVolume = audibleVolume(for: category)
        }
        applyVolumesToSources()
    }

    /// Pushes the camera pose into the environment node, converting Skyrim's
    /// Z-up native-unit world into the Y-up meter listener space (AudioSpace).
    public func updateListener(worldPosition: SIMD3<Float>, yaw: Float, pitch: Float) {
        listenerWorldPosition = worldPosition
        let position = AudioSpace.listenerPosition(fromWorld: worldPosition)
        environment.listenerPosition = AVAudio3DPoint(
            x: position.x, y: position.y, z: position.z
        )
        let forward = AudioSpace.listenerDirection(
            fromWorld: AudioSpace.worldForward(yaw: yaw, pitch: pitch)
        )
        let upward = AudioSpace.listenerDirection(
            fromWorld: AudioSpace.worldUp(yaw: yaw, pitch: pitch)
        )
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(
            forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z),
            up: AVAudio3DVector(x: upward.x, y: upward.y, z: upward.z)
        )
    }

    /// Per-frame housekeeping, driven by Renderer.updateAudio: advance gain
    /// ramps by the frame delta, retire sources whose stream completed, and
    /// stop sources the world streamed away from. `deltaTime` is in seconds and
    /// comes from the renderer's paused-aware audio clock, so fades freeze in
    /// menu mode and never jump on resume. Zero advances nothing.
    public func tick(listenerCell: CellCoordinate, deltaTime: Float = 0) {
        liveClockSeconds += Double(max(0, deltaTime))
        for source in sources {
            source.voiceClock?.publish(max(0, playbackClockSeconds - source.startClockSeconds))
        }
        advanceFades(deltaTime: deltaTime)
        advanceReverb(deltaTime: deltaTime)
        updateDistanceGains()
        retireFinishedSources()
        purgeSources(fartherThan: Self.cellPurgeRadius, fromCell: listenerCell)
    }

    // MARK: - Graph lifecycle

    private func buildGraph() {
        engine.attach(environment)
        environment.distanceAttenuationParameters.distanceAttenuationModel = .inverse
        environment.distanceAttenuationParameters.referenceDistance =
            ProvisionalAttenuation.referenceDistanceMeters
        environment.distanceAttenuationParameters.maximumDistance =
            ProvisionalAttenuation.maximumDistanceMeters
        environment.distanceAttenuationParameters.rolloffFactor =
            ProvisionalAttenuation.rolloffFactor
        for category in AudioCategory.allCases {
            let mixer = AVAudioMixerNode()
            engine.attach(mixer)
            categoryMixers[category] = mixer
        }
    }

    /// Environment + submixes connect lazily on first start so the output
    /// format (device or manual) is known.
    private func connectGraphIfNeeded() {
        guard engine.outputConnectionPoints(for: environment, outputBus: 0).isEmpty else {
            return
        }
        let mixFormat = AVAudioFormat(
            standardFormatWithSampleRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
            channels: 2
        )
        engine.connect(environment, to: engine.mainMixerNode, format: mixFormat)
        for mixer in categoryMixers.values {
            engine.connect(mixer, to: engine.mainMixerNode, format: mixFormat)
        }
        for (category, mixer) in categoryMixers {
            mixer.outputVolume = audibleVolume(for: category)
        }
        engine.mainMixerNode.outputVolume = masterVolume
    }

    private func startEngine() {
        do {
            if let manualRenderingFormat, engine.manualRenderingMode != .offline {
                try engine.enableManualRenderingMode(
                    .offline, format: manualRenderingFormat, maximumFrameCount: 4096
                )
            }
            connectGraphIfNeeded()
            try engine.start()
            unavailableReason = nil
        } catch {
            unavailableReason = String(describing: error)
        }
    }

    private func stopEngine() {
        stopAllSources()
        engine.stop()
        unavailableReason = nil
    }
}
