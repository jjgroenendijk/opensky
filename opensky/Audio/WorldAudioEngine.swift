// World audio playback graph (milestone 9.1.3): one AVAudioEngine with an
// AVAudioEnvironmentNode for 3D mixing, one submix per vanilla menu category, and
// the main mixer as master volume. Source lifecycle lives in
// WorldAudioEngineSources.swift; the full graph, threading model and coordinate
// conversion are documented in docs/engine/audio.md.
//
// Graph:
//   positional AVAudioPlayerNode (mono) --> environment node --> main mixer
//   category submix mixers (music and ambience beds) ------>--/
// Positional inputs must be mono — the environment node passes stereo through
// without spatializing — so streamers downmix. Category volume for a positional
// source is applied at its player node (effective gain = master x category x
// source); the submix mixers carry the same category volumes for music and
// ambience beds, so the two paths cannot disagree.
//
// Threading: this class is main-actor only. Decode work runs on `decodeQueue`
// (see AudioSourceStreamer); the audio render thread runs no OpenSky code.

import AVFAudio
import Foundation
import simd

nonisolated enum AudioEngineError: Error, Equatable {
    /// Playback was requested while the engine is disabled or failed to start.
    case notRunning
    /// A pcm format could not be constructed for the source's sample rate.
    case formatUnavailable
    /// The category submix a non-positional source needs is missing from the
    /// graph. Cannot happen while every `AudioCategory` gets a mixer; it exists
    /// so the play path never force-unwraps.
    case submixUnavailable
}

/// Provisional distance-attenuation defaults, in meters (the listener-space
/// unit AudioSpace fixes). Game-authored values arrive in M9.2 from sound
/// descriptor records; until then these are tuned only to make the World >
/// Audio verification audible and obviously direction/distance dependent.
nonisolated enum ProvisionalAttenuation {
    /// Distance at which a source plays at full gain (~2 m).
    static let referenceDistanceMeters: Float = 2
    /// Attenuation stops growing past this distance (~one exterior cell).
    static let maximumDistanceMeters: Float = 60
    static let rolloffFactor: Float = 1
}

@MainActor
final class WorldAudioEngine {
    /// Concurrent-source budget. Provisional; the eviction rule is FIFO — see
    /// `makeRoomForNewSource()` in WorldAudioEngineSources.swift.
    static let maxConcurrentSources = 8
    /// Sources bound to a cell farther than this (Chebyshev rings) from the
    /// listener's cell are stopped on the audio tick — cleanup when the world
    /// streams away. One ring beyond the streamer's default 5x5 residency.
    static let cellPurgeRadius: Int32 = 3

    let engine = AVAudioEngine()
    let environment = AVAudioEnvironmentNode()
    private(set) var categoryMixers: [AudioCategory: AVAudioMixerNode] = [:]
    /// Serial owner of every WMADecoder and all streaming state.
    let decodeQueue = DispatchQueue(
        label: "nl.jjgroenendijk.opensky.audio-decode",
        qos: .userInitiated
    )

    /// Playing sources, oldest first (append order = start order, which is what
    /// the FIFO eviction walks). Written only by WorldAudioEngineSources.swift;
    /// internal rather than private(set) because that file is a satellite.
    var sources: [ActiveAudioSource] = []
    /// Next source id; taken only by WorldAudioEngineSources.swift.
    var nextSourceID = 1
    /// Why the graph is not running, for the panel readout. nil while healthy.
    private(set) var unavailableReason: String?
    /// Listener pose in world space, kept for the snapshot's distance column.
    private(set) var listenerWorldPosition = SIMD3<Float>.zero

    /// Off by default: no audio engine starts (and no output device is touched)
    /// until the user enables it in World > Audio.
    var isEnabled = false {
        didSet {
            guard isEnabled != oldValue else { return }
            if isEnabled {
                startEngine()
            } else {
                stopEngine()
            }
        }
    }

    var isRunning: Bool {
        engine.isRunning
    }

    var masterVolume: Float = 1 {
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
    var soloedCategory: AudioCategory? {
        didSet {
            guard soloedCategory != oldValue else { return }
            applyCategoryGains()
        }
    }

    /// Offline manual-rendering hook for deterministic tests. Production passes
    /// nil and renders to the output device.
    private let manualRenderingFormat: AVAudioFormat?

    init(manualRenderingFormat: AVAudioFormat? = nil) {
        self.manualRenderingFormat = manualRenderingFormat
        buildGraph()
    }

    func volume(for category: AudioCategory) -> Float {
        categoryVolumes[category] ?? 1
    }

    func setVolume(_ volume: Float, for category: AudioCategory) {
        categoryVolumes[category] = simd_clamp(volume, 0, 1)
        applyCategoryGains()
    }

    func isMuted(_ category: AudioCategory) -> Bool {
        mutedCategories.contains(category)
    }

    /// Mutes or unmutes one category. The category's volume is untouched, so
    /// unmuting restores exactly the level the slider was left at.
    func setMuted(_ muted: Bool, for category: AudioCategory) {
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
    func audibleVolume(for category: AudioCategory) -> Float {
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
    func updateListener(worldPosition: SIMD3<Float>, yaw: Float, pitch: Float) {
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
    func tick(listenerCell: CellCoordinate, deltaTime: Float = 0) {
        advanceFades(deltaTime: deltaTime)
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
