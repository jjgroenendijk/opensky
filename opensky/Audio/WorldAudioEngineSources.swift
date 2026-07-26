// Positional source lifecycle for WorldAudioEngine: start, budget/eviction,
// finished-stream retirement, cell-unload purge. Split from
// WorldAudioEngine.swift (graph + volumes) to stay inside the file-size limits.

import AVFAudio
import Foundation
import simd

/// One playing positional source. Reference type: identity is what the
/// eviction, retirement and panel rows track.
@MainActor
final class ActiveAudioSource {
    let id: Int
    /// Display name (the VFS path of the file being played).
    let name: String
    let category: AudioCategory
    /// World position in native Skyrim units.
    let worldPosition: SIMD3<Float>
    /// Exterior cell the position falls in — the purge key for cell unload.
    let cell: CellCoordinate
    /// Per-source gain, multiplied with the category and master volumes.
    let gain: Float
    /// Continuous source: it restarts at the beginning instead of ending.
    let loops: Bool
    let node: AVAudioPlayerNode
    /// nil for buffer-backed test sources; streamed sources own their decoder
    /// through this.
    let streamer: AudioSourceStreamer?

    init(
        id: Int,
        request: AudioPlayRequest,
        node: AVAudioPlayerNode,
        streamer: AudioSourceStreamer?
    ) {
        self.id = id
        name = request.name
        category = request.category
        worldPosition = request.worldPosition
        cell = CellGridManager.cellCoordinate(for: request.worldPosition)
        gain = request.gain
        loops = request.loops
        self.node = node
        self.streamer = streamer
    }
}

/// Everything a positional playback needs, as one value (the 5-parameter limit
/// and call-site readability both want a struct here).
nonisolated struct AudioPlayRequest {
    let name: String
    let category: AudioCategory
    let worldPosition: SIMD3<Float>
    var gain: Float = 1
    /// Continuous playback: the source restarts at the beginning instead of
    /// ending. Ambience beds set this; one-shot effects do not.
    var loops = false
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
            id: takeSourceID(), request: request, node: node, streamer: streamer
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
            id: takeSourceID(), request: request, node: node, streamer: nil
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
    /// ring distance beyond `radius`).
    func purgeSources(fartherThan radius: Int32, fromCell center: CellCoordinate) {
        for source in sources {
            let distance = max(
                abs(source.cell.x - center.x), abs(source.cell.y - center.y)
            )
            if distance > radius {
                stop(source)
            }
        }
    }

    /// Re-applies category x source gain to every player node (master volume
    /// lives on the main mixer, so it is deliberately not part of this product).
    func applyVolumesToSources() {
        for source in sources {
            source.node.volume = volume(for: source.category) * source.gain
        }
    }

    /// Effective gain of one source as the listener hears it before distance
    /// attenuation: master x category x source.
    func effectiveGain(of source: ActiveAudioSource) -> Float {
        masterVolume * volume(for: source.category) * source.gain
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

    /// Budget rule: at `maxConcurrentSources`, starting a new source evicts the
    /// oldest playing one (FIFO by start order). Oldest-first is predictable,
    /// cheap, and matches how short one-shot effects naturally expire; a
    /// priority scheme waits for game-authored data in M9.2.
    private func makeRoomForNewSource() {
        while sources.count >= Self.maxConcurrentSources, let oldest = sources.first {
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
