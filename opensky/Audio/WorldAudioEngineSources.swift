// Source lifecycle for WorldAudioEngine: start (positional and
// non-positional), budget/eviction, finished-stream retirement, cell-unload
// purge. Split from WorldAudioEngine.swift (graph + volumes) to stay inside the
// file-size limits; gain ramps live in WorldAudioEngineFades.swift.

import AVFAudio
import Foundation
import simd

/// How a source reaches the main mixer. Explicit rather than inferred from the
/// category, so a caller can see which path it asked for.
nonisolated enum AudioRouting: String, Sendable {
    /// Mono player node spatialized by the environment node.
    case positional
    /// Stereo player node wired straight into the category submix, with no
    /// distance attenuation, no panning and no world position.
    case nonPositional
}

/// One playing source. Reference type: identity is what the eviction,
/// retirement and panel rows track.
@MainActor
final class ActiveAudioSource {
    let id: Int
    /// Display name (the VFS path of the file being played).
    let name: String
    let category: AudioCategory
    let routing: AudioRouting
    /// World position in native Skyrim units. Meaningless (and always zero)
    /// for a non-positional source.
    let worldPosition: SIMD3<Float>
    /// Exterior cell the position falls in — the purge key for cell unload.
    let cell: CellCoordinate
    /// Per-source gain, multiplied with the category, master and fade gains.
    let gain: Float
    /// Continuous source: it restarts at the beginning instead of ending.
    let loops: Bool
    let node: AVAudioPlayerNode
    /// nil for buffer-backed test sources; streamed sources own their decoder
    /// through this.
    let streamer: AudioSourceStreamer?
    /// Fade multiplier in [0, 1], folded into the node volume on top of `gain`.
    /// Owned by WorldAudioEngineFades.swift (internal because that file is a
    /// satellite of this one).
    var fadeGain: Float = 1
    /// Ramp in flight, or nil when the fade gain is holding steady. Also owned
    /// by WorldAudioEngineFades.swift.
    var activeFade: GainFade?

    var isPositional: Bool {
        routing == .positional
    }

    init(
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
        cell = CellGridManager.cellCoordinate(for: position)
        gain = request.gain
        loops = request.loops
        self.node = node
        self.streamer = streamer
    }
}

/// Everything a playback request needs, as one value (the 5-parameter limit
/// and call-site readability both want a struct here). `worldPosition` is
/// ignored by the non-positional path.
nonisolated struct AudioPlayRequest {
    let name: String
    let category: AudioCategory
    let worldPosition: SIMD3<Float>
    var gain: Float = 1
    /// Continuous playback: the source restarts at the beginning instead of
    /// ending. Ambience beds and music tracks set this; one-shot effects do
    /// not.
    var loops = false

    /// Request for a source with no world position — music beds and other 2D
    /// material routed straight into a category submix.
    static func nonPositional(
        name: String,
        category: AudioCategory,
        gain: Float = 1,
        loops: Bool = false
    ) -> AudioPlayRequest {
        AudioPlayRequest(
            name: name, category: category, worldPosition: .zero, gain: gain, loops: loops
        )
    }
}

extension WorldAudioEngine {
    /// Starts a positional streamed source from framed `.xwm` bytes. Decode
    /// runs on the decode queue; this only builds and wires the player node.
    /// Returns the new source's id so the caller can retire exactly it later.
    @discardableResult
    func playPositional(fileData: Data, request: AudioPlayRequest) throws -> Int {
        guard isRunning else { throw AudioEngineError.notRunning }
        let file = try XWMFile(data: fileData)
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
    func playPositional(buffer: AVAudioPCMBuffer, request: AudioPlayRequest) throws -> Int {
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
        node.scheduleBuffer(
            buffer, at: nil, options: request.loops ? .loops : [], completionHandler: nil
        )
        node.play()
        return source.id
    }

    /// Starts a non-positional streamed source from framed `.xwm` bytes: the
    /// file's own channel layout (no mono downmix), wired into the category
    /// submix instead of the environment node. This is the music path — it
    /// never pans, never attenuates with distance, and is exempt from both the
    /// concurrent-source cap and the cell purge.
    @discardableResult
    func playNonPositional(fileData: Data, request: AudioPlayRequest) throws -> Int {
        guard isRunning else { throw AudioEngineError.notRunning }
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
    func playNonPositional(buffer: AVAudioPCMBuffer, request: AudioPlayRequest) throws -> Int {
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
        node.scheduleBuffer(
            buffer, at: nil, options: request.loops ? .loops : [], completionHandler: nil
        )
        node.play()
        return source.id
    }

    func stopAllSources() {
        while let source = sources.first {
            stop(source)
        }
    }

    /// Stops one source by id. Returns true when a source was stopped. Used by
    /// the world sound director to retire ambience beds without losing
    /// unrelated one-shot SFX (issue #155).
    @discardableResult
    func stopSource(id: Int) -> Bool {
        guard let source = sources.first(where: { $0.id == id }) else { return false }
        stop(source)
        return true
    }

    /// Detaches sources whose stream reported completion. Called from the
    /// per-frame audio tick.
    func retireFinishedSources() {
        for source in sources where source.streamer?.isFinished == true {
            stop(source)
        }
    }

    /// Stops sources bound to cells the world streamed away from (Chebyshev
    /// ring distance beyond `radius`). Non-positional sources have no
    /// meaningful cell, so they are exempt: a music bed must survive the world
    /// streaming around it.
    func purgeSources(fartherThan radius: Int32, fromCell center: CellCoordinate) {
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
    func applyVolumesToSources() {
        for source in sources {
            applyVolume(to: source)
        }
    }

    /// Pushes one source's node-level gain product.
    ///
    /// Category volume is applied exactly once per source: a positional source
    /// bypasses the submixes (each needs its own environment-node input), so it
    /// carries the category factor at its node; a non-positional source already
    /// passes through the category submix, which carries it. Master volume
    /// lives on the main mixer and is never part of this product.
    func applyVolume(to source: ActiveAudioSource) {
        let categoryFactor = source.isPositional ? volume(for: source.category) : 1
        source.node.volume = categoryFactor * source.gain * source.fadeGain
    }

    /// Effective gain of one source as the listener hears it before distance
    /// attenuation: master x category x source x fade.
    func effectiveGain(of source: ActiveAudioSource) -> Float {
        masterVolume * volume(for: source.category) * source.gain * source.fadeGain
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
        // Equal-power panning is deterministic and cheap; HRTF selection is a
        // later, provisional-free decision alongside the M9.2 attenuation data.
        node.renderingAlgorithm = .equalPowerPanning
        let position = AudioSpace.listenerPosition(fromWorld: request.worldPosition)
        node.position = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        node.volume = volume(for: request.category) * request.gain
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

    /// Budget rule: at `maxConcurrentSources` positional sources, starting
    /// another one evicts the oldest playing positional source (FIFO by start
    /// order). Oldest-first is predictable, cheap, and matches how short
    /// one-shot effects naturally expire; a priority scheme waits for
    /// game-authored data in M9.2. Non-positional sources are outside the
    /// budget entirely — a music bed must not be evicted by a burst of SFX.
    private func makeRoomForNewSource() {
        while
            sources.count(where: \.isPositional) >= Self.maxConcurrentSources,
            let oldest = sources.first(where: \.isPositional)
        {
            stop(oldest)
        }
    }

    private func adoptSource(_ source: ActiveAudioSource) {
        sources.append(source)
    }

    private func takeSourceID() -> Int {
        defer { nextSourceID += 1 }
        return nextSourceID
    }

    private func stop(_ source: ActiveAudioSource) {
        source.streamer?.requestStop()
        source.node.stop()
        engine.detach(source.node)
        sources.removeAll { $0 === source }
    }
}
