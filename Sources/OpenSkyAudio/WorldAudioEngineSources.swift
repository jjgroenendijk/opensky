// Source lifecycle for WorldAudioEngine: start (positional and
// non-positional), budget/eviction, finished-stream retirement, cell-unload
// purge. Split from WorldAudioEngine.swift (graph + volumes) to stay inside the
// file-size limits; gain ramps live in WorldAudioEngineFades.swift.

import AVFAudio
import Foundation
import OpenSkyFormatsAudio
import OpenSkyFormatsCore
import simd

/// How a source reaches the main mixer. Explicit rather than inferred from the
/// category, so a caller can see which path it asked for.
nonisolated public enum AudioRouting: String, Sendable {
    /// Mono player node spatialized by the environment node.
    case positional
    /// Stereo player node wired straight into the category submix, with no
    /// distance attenuation, no panning and no world position.
    case nonPositional
}

/// One playing source. Reference type: identity is what the eviction,
/// retirement and panel rows track.
@MainActor
public final class ActiveAudioSource {
    public let id: Int
    /// Display name (the VFS path of the file being played).
    public let name: String
    public let category: AudioCategory
    public let routing: AudioRouting
    /// World position in native Skyrim units. Meaningless (and always zero)
    /// for a non-positional source.
    public let worldPosition: SIMD3<Float>
    /// Exterior cell the position falls in — the purge key for cell unload.
    public let cell: CellCoordinate
    /// Per-source gain, multiplied with the category, master and fade gains.
    public let gain: Float
    /// Continuous source: it restarts at the beginning instead of ending.
    public let loops: Bool
    public let node: AVAudioPlayerNode
    /// nil for buffer-backed sources; streamed sources own their decoder
    /// through this.
    public let streamer: AudioSourceStreamer?
    /// Engine playback clock at the moment this source started, which is what
    /// `playbackPosition(ofSource:)` subtracts from. Written by `adoptSource`
    /// rather than by `init`, because the clock belongs to the engine.
    public var startClockSeconds: Double = 0
    /// Set when a buffer source has played out. Without it a one-shot `.wav` stays in
    /// `sources` until evicted, which leaks with footsteps. Set on the main actor;
    /// read by `retireFinishedSources`.
    public var bufferFinished = false
    /// Fade multiplier in [0, 1], folded into the node volume on top of `gain`.
    /// Owned by WorldAudioEngineFades.swift (internal because that file is a
    /// satellite of this one).
    public var fadeGain: Float = 1
    /// Ramp in flight, or nil when the fade gain is holding steady. Also owned
    /// by WorldAudioEngineFades.swift.
    public var activeFade: GainFade?
    /// Nonisolated snapshot read by one actor's LipSyncPlayback. Voice sources
    /// attach it after adoption; every other audio source leaves it nil.
    public var voiceClock: VoicePlaybackClock?

    public var isPositional: Bool {
        routing == .positional
    }

    public init(
        id: Int,
        request: AudioPlayRequest,
        routing: AudioRouting,
        node: AVAudioPlayerNode,
        streamer: AudioSourceStreamer?
    ) {
        self.id = id
        name = request.name
        category = request.category
        self.routing = routing
        let position = routing == .positional ? request.worldPosition : .zero
        worldPosition = position
        cell = CellCoordinate(containing: position)
        gain = request.gain
        loops = request.loops
        self.node = node
        self.streamer = streamer
    }
}

/// Everything a playback request needs, as one value (the 5-parameter limit
/// and call-site readability both want a struct here). `worldPosition` is
/// ignored by the non-positional path.
nonisolated public struct AudioPlayRequest: Sendable {
    public let name: String
    public let category: AudioCategory
    public let worldPosition: SIMD3<Float>
    public var gain: Float = 1
    /// Continuous playback: the source restarts at the beginning instead of
    /// ending. Ambience beds and music tracks set this; one-shot effects do
    /// not.
    public var loops = false

    /// Request for a source with no world position — music, ambience and other
    /// 2D material routed straight into a category submix.
    public static func nonPositional(
        name: String,
        category: AudioCategory,
        gain: Float = 1,
        loops: Bool = false
    ) -> AudioPlayRequest {
        AudioPlayRequest(
            name: name, category: category, worldPosition: .zero, gain: gain, loops: loops
        )
    }

    public init(
        name: String,
        category: AudioCategory,
        worldPosition: SIMD3<Float>,
        gain: Float = 1,
        loops: Bool = false
    ) {
        self.name = name
        self.category = category
        self.worldPosition = worldPosition
        self.gain = gain
        self.loops = loops
    }
}

extension WorldAudioEngine {
    /// Starts a positional streamed source from framed `.xwm` bytes. Decode
    /// runs on the decode queue; this only builds and wires the player node.
    /// Returns the new source's id so the caller can retire exactly it later.
    @discardableResult
    public func playPositional(fileData: Data, request: AudioPlayRequest) throws -> Int {
        guard isRunning else { throw AudioEngineError.notRunning }
        if Self.isWAV(fileData) {
            // Sound effects — footsteps, doors, activators — ship as plain
            // RIFF/WAVE, which needs no decoder and no streaming; see
            // WorldAudioEngineWAV.swift.
            return try playPositional(
                buffer: Self.makeBuffer(wav: fileData, downmixToMono: true),
                request: request
            )
        }
        return try playPositional(file: XWMFile(data: fileData), request: request)
    }

    /// Starts a positional streamed source from an already-framed container.
    /// The voice path frames its own `.fuz` first and enters here, so a voice
    /// line and a positional `.xwm` effect share one code path from the player
    /// node down.
    @discardableResult
    public func playPositional(file: XWMFile, request: AudioPlayRequest) throws -> Int {
        guard isRunning else { throw AudioEngineError.notRunning }
        // Positional inputs must be mono: the environment node spatializes
        // mono and passes stereo through flat.
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(file.codec.sampleRate), channels: 1
            )
        else {
            throw AudioEngineError.formatUnavailable
        }
        let node = makePositionalNode(request: request, format: format)
        let streamer = AudioSourceStreamer(
            file: file,
            node: node,
            format: format,
            downmixToMono: file.codec.channelCount > 1,
            loops: request.loops,
            queue: decodeQueue
        )
        let source = ActiveAudioSource(
            id: takeSourceID(),
            request: request,
            routing: .positional,
            node: node,
            streamer: streamer
        )
        adoptSource(source)
        streamer.start()
        node.play()
        return source.id
    }

    /// Starts a positional source from an already-built PCM buffer. Test seam:
    /// the deterministic offline-render tests use this so no decoder or decode
    /// queue timing is involved. A looping request re-plays the buffer through
    /// the player node's own loop option.
    @discardableResult
    public func playPositional(buffer: AVAudioPCMBuffer, request: AudioPlayRequest) throws -> Int {
        guard isRunning else { throw AudioEngineError.notRunning }
        let node = makePositionalNode(request: request, format: buffer.format)
        let source = ActiveAudioSource(
            id: takeSourceID(),
            request: request,
            routing: .positional,
            node: node,
            streamer: nil
        )
        adoptSource(source)
        schedule(buffer, on: node, for: source, loops: request.loops)
        node.play()
        return source.id
    }

    /// Starts a non-positional streamed source from framed `.xwm` bytes: the
    /// file's own channel layout (no mono downmix), wired into the category
    /// submix instead of the environment node. This is the 2D-bed path — it
    /// never pans, never attenuates with distance, and is exempt from both the
    /// concurrent-source cap and the cell purge.
    @discardableResult
    public func playNonPositional(fileData: Data, request: AudioPlayRequest) throws -> Int {
        guard isRunning else { throw AudioEngineError.notRunning }
        if Self.isWAV(fileData) {
            return try playNonPositional(
                buffer: Self.makeBuffer(wav: fileData, downmixToMono: false),
                request: request
            )
        }
        let file = try XWMFile(data: fileData)
        let channels = AVAudioChannelCount(file.codec.channelCount)
        guard
            channels > 0,
            let format = AVAudioFormat(
                standardFormatWithSampleRate: Double(file.codec.sampleRate), channels: channels
            )
        else {
            throw AudioEngineError.formatUnavailable
        }
        let node = try makeNonPositionalNode(request: request, format: format)
        let streamer = AudioSourceStreamer(
            file: file,
            node: node,
            format: format,
            downmixToMono: false,
            loops: request.loops,
            queue: decodeQueue
        )
        let source = ActiveAudioSource(
            id: takeSourceID(),
            request: request,
            routing: .nonPositional,
            node: node,
            streamer: streamer
        )
        adoptSource(source)
        streamer.start()
        node.play()
        return source.id
    }

    /// Non-positional playback from an already-built PCM buffer. Test seam,
    /// mirroring `playPositional(buffer:request:)`.
    @discardableResult
    public func playNonPositional(
        buffer: AVAudioPCMBuffer,
        request: AudioPlayRequest
    ) throws -> Int {
        guard isRunning else { throw AudioEngineError.notRunning }
        let node = try makeNonPositionalNode(request: request, format: buffer.format)
        let source = ActiveAudioSource(
            id: takeSourceID(),
            request: request,
            routing: .nonPositional,
            node: node,
            streamer: nil
        )
        adoptSource(source)
        schedule(buffer, on: node, for: source, loops: request.loops)
        node.play()
        return source.id
    }

    /// Schedules one buffer; a one-shot is retired once it plays out. The completion
    /// handler hops to the main actor. A looping source gets no handler.
    private func schedule(
        _ buffer: AVAudioPCMBuffer,
        on node: AVAudioPlayerNode,
        for source: ActiveAudioSource,
        loops: Bool
    ) {
        guard !loops else {
            node.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
            return
        }
        node.scheduleBuffer(buffer, at: nil, options: []) {
            Task { @MainActor in
                source.bufferFinished = true
            }
        }
    }

    public func stopAllSources() {
        while let source = sources.first {
            stop(source)
        }
    }

    /// Stops one source by id. Returns true when a source was stopped. The sound
    /// director retires ambience beds this way without touching one-shot SFX.
    @discardableResult
    public func stopSource(id: Int) -> Bool {
        guard let source = sources.first(where: { $0.id == id }) else { return false }
        stop(source)
        return true
    }

    /// Detaches sources whose stream completed; called from the audio tick.
    /// `onSourceFinished` fires only here, so it means "played to the end", not
    /// stopped or evicted. Dialogue subtitles rely on that.
    public func retireFinishedSources() {
        for source in sources where source.streamer?.isFinished == true || source.bufferFinished {
            let id = source.id
            stop(source)
            onSourceFinished?(id)
        }
    }

    /// Stops sources bound to cells the world streamed away from (Chebyshev
    /// ring distance beyond `radius`). Non-positional sources have no
    /// meaningful cell, so they are exempt: music and ambience beds must
    /// survive the world streaming around them.
    public func purgeSources(fartherThan radius: Int32, fromCell center: CellCoordinate) {
        for source in sources where source.isPositional {
            let distance = max(
                abs(source.cell.x - center.x), abs(source.cell.y - center.y)
            )
            if distance > radius {
                stop(source)
            }
        }
    }

    /// Re-applies the node-level gain product to every player node. Folding the
    /// fade in here is what keeps a volume-slider move from stomping an
    /// in-flight ramp.
    public func applyVolumesToSources() {
        for source in sources {
            applyVolume(to: source)
        }
    }

    /// Pushes one source's node gain. Category volume applies once: at the node for a
    /// positional source, at the submix otherwise. Master lives on the main mixer.
    /// `audibleVolume(for:)` applies mute and solo on both paths.
    public func applyVolume(to source: ActiveAudioSource) {
        let categoryFactor = source.isPositional ? audibleVolume(for: source.category) : 1
        source.node.volume = categoryFactor * source.gain * source.fadeGain
    }

    /// Effective gain of one source as the listener hears it before distance
    /// attenuation: master x category x source x fade, where the category
    /// factor is zero while the category is muted or another one is soloed.
    public func effectiveGain(of source: ActiveAudioSource) -> Float {
        masterVolume * audibleVolume(for: source.category) * source.gain * source.fadeGain
    }

    // MARK: - Internals

    private func makePositionalNode(
        request: AudioPlayRequest,
        format: AVAudioFormat
    ) -> AVAudioPlayerNode {
        makeRoomForNewSource()
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: environment, format: format)
        // Equal-power panning is deterministic and cheap; HRTF waits for the
        // authored attenuation data.
        node.renderingAlgorithm = .equalPowerPanning
        let position = AudioSpace.listenerPosition(fromWorld: request.worldPosition)
        node.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        node.volume = audibleVolume(for: request.category) * request.gain
        return node
    }

    /// Non-positional node: stereo (or whatever the material carries) straight
    /// into the category submix, with no 3D position and no rendering
    /// algorithm. Exempt from the concurrent-source budget, so it never evicts
    /// a positional source and is never evicted by one.
    private func makeNonPositionalNode(
        request: AudioPlayRequest,
        format: AVAudioFormat
    ) throws -> AVAudioPlayerNode {
        guard let mixer = categoryMixers[request.category] else {
            throw AudioEngineError.submixUnavailable
        }
        let node = AVAudioPlayerNode()
        engine.attach(node)
        engine.connect(node, to: mixer, format: format)
        // Category volume is the submix's job on this path; see applyVolume.
        node.volume = request.gain
        return node
    }

    /// At `maxConcurrentSources` positional sources, a new one evicts the oldest
    /// (FIFO): predictable, and short effects expire first anyway. Non-positional
    /// beds are outside the budget, so SFX cannot evict them.
    private func makeRoomForNewSource() {
        while
            sources.count(where: \.isPositional) >= Self.maxConcurrentSources,
            let oldest = sources.first(where: \.isPositional)
        {
            stop(oldest)
        }
    }

    private func adoptSource(_ source: ActiveAudioSource) {
        source.startClockSeconds = playbackClockSeconds
        sources.append(source)
    }

    private func takeSourceID() -> Int {
        defer { nextSourceID += 1 }
        return nextSourceID
    }

    private func stop(_ source: ActiveAudioSource) {
        source.voiceClock?.publish(nil)
        source.streamer?.requestStop()
        source.node.stop()
        engine.detach(source.node)
        sources.removeAll { $0 === source }
    }
}
