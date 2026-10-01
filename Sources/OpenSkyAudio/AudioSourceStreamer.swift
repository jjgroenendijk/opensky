// Streaming decode for one playing source: keeps an `AVAudioPlayerNode` fed
// with short PCM buffers instead of decoding the whole file up front.
// Threading model: docs/engine/audio.md. No code in this file runs on the audio
// render thread, so the locks here never block it.

@preconcurrency import AVFAudio
import Foundation
import OpenSkyFormatsAudio
import Synchronization

nonisolated public final class AudioSourceStreamer: Sendable {
    /// At vanilla music rates one packet decodes to about 46 ms of PCM, so a
    /// chunk is about 0.75 s.
    public static let packetsPerChunk = 16
    /// Refill starts when one buffer finishes, so about 1.5 s of margin remains.
    public static let maxChunksInFlight = 3

    /// Decode state. Only the decode queue locks it, so the lock never waits.
    nonisolated private struct DecodeState {
        var decoder: WMADecoder?
        var nextPacketIndex = 0
        var chunksInFlight = 0
        var drained = false
        var stopped = false
        /// A looping pass that decoded nothing ends instead of rewinding, so an
        /// unusable file never spins the decode queue.
        var passProducedSamples = false
    }

    private let queue: DispatchQueue
    private let node: AVAudioPlayerNode
    private let format: AVAudioFormat
    private let file: XWMFile
    private let downmixToMono: Bool
    /// The per-cell ambient bed rewinds at end of file, so it never finishes.
    private let loops: Bool
    private let state = Mutex(DecodeState())
    /// Polled by the main actor each audio tick.
    private let finished = Mutex(false)

    public var isFinished: Bool {
        finished.withLock { $0 }
    }

    /// - Parameters:
    ///   - node: the player this streamer feeds. The engine attaches it.
    ///   - format: the node's connection format, mono for positional sources.
    ///   - downmixToMono: the environment node plays stereo flat, unpositioned.
    ///   - queue: the engine's shared serial decode queue.
    public init(
        file: XWMFile,
        node: AVAudioPlayerNode,
        format: AVAudioFormat,
        downmixToMono: Bool,
        loops: Bool = false,
        queue: DispatchQueue
    ) {
        self.file = file
        self.node = node
        self.format = format
        self.downmixToMono = downmixToMono
        self.loops = loops
        self.queue = queue
    }

    /// Starts decoding on the decode queue. The caller starts the player node.
    public func start() {
        queue.async { [self] in
            let parameters = AudioCodecParameters(xwm: file.codec)
            let started = state.withLock { decode in
                decode.decoder = try? WMADecoder(parameters: parameters)
                guard decode.decoder != nil else { return false }
                scheduleMore(&decode)
                return true
            }
            if !started {
                markFinished()
            }
        }
    }

    /// The engine also stops the node, which drops scheduled buffers and fires
    /// their completions; this flag stops the queue from scheduling more.
    public func requestStop() {
        queue.async { [self] in
            state.withLock { $0.stopped = true }
            markFinished()
        }
    }

    // MARK: - Decode queue

    private func scheduleMore(_ decode: inout DecodeState) {
        while !decode.stopped, !decode.drained, decode.chunksInFlight < Self.maxChunksInFlight {
            guard let samples = decodeNextChunk(&decode), !samples.isEmpty else { continue }
            guard
                let buffer = Self.makeBuffer(
                    samples: samples,
                    sourceChannelCount: file.codec.channelCount,
                    downmixToMono: downmixToMono,
                    format: format
                )
            else {
                decode.drained = true
                break
            }
            decode.chunksInFlight += 1
            // Completion fires on an AVFAudio queue; hop back to the decode queue.
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                queue.async { self.chunkCompleted() }
            }
        }
        if decode.drained, decode.chunksInFlight == 0 {
            markFinished()
        }
    }

    /// Decodes up to `packetsPerChunk` packets. Returns nil after a decode
    /// error, so the source ends early but never traps.
    private func decodeNextChunk(_ decode: inout DecodeState) -> [Float]? {
        guard let decoder = decode.decoder else {
            decode.drained = true
            return nil
        }
        var samples: [Float] = []
        var packetsUsed = 0
        do {
            while packetsUsed < Self.packetsPerChunk {
                guard let packet = file.packet(at: decode.nextPacketIndex) else {
                    let tail = try decoder.flush()
                    append(tail, to: &samples, state: &decode)
                    rewindOrDrain(&decode, decoder: decoder)
                    break
                }
                decode.nextPacketIndex += 1
                packetsUsed += 1
                try append(decoder.decode(packet: packet), to: &samples, state: &decode)
            }
        } catch {
            decode.drained = true
            return nil
        }
        return samples
    }

    private func append(_ decoded: [Float], to samples: inout [Float], state: inout DecodeState) {
        guard !decoded.isEmpty else { return }
        state.passProducedSamples = true
        samples.append(contentsOf: decoded)
    }

    private func rewindOrDrain(_ decode: inout DecodeState, decoder: WMADecoder) {
        guard
            Self.shouldRewind(
                loops: loops,
                passProducedSamples: decode.passProducedSamples,
                stopped: decode.stopped
            )
        else {
            decode.drained = true
            return
        }
        decoder.reset()
        decode.nextPacketIndex = 0
        decode.passProducedSamples = false
    }

    private func chunkCompleted() {
        state.withLock { decode in
            decode.chunksInFlight -= 1
            if decode.drained || decode.stopped {
                if decode.chunksInFlight <= 0 {
                    markFinished()
                }
                return
            }
            scheduleMore(&decode)
        }
    }

    private func markFinished() {
        finished.withLock { $0 = true }
    }

    // MARK: - Policy + PCM packing (pure, unit-tested)

    /// Kept pure so a unit test can check it: no WMA fixture may enter the repo.
    public static func shouldRewind(loops: Bool, passProducedSamples: Bool, stopped: Bool) -> Bool {
        loops && passProducedSamples && !stopped
    }

    /// Averages interleaved multi-channel PCM into one mono channel.
    public static func monoDownmix(_ interleaved: [Float], channelCount: Int) -> [Float] {
        guard channelCount > 1 else { return interleaved }
        let frameCount = interleaved.count / channelCount
        var mono = [Float](repeating: 0, count: frameCount)
        let scale = 1 / Float(channelCount)
        for frame in 0 ..< frameCount {
            var sum: Float = 0
            for channel in 0 ..< channelCount {
                sum += interleaved[frame * channelCount + channel]
            }
            mono[frame] = sum * scale
        }
        return mono
    }

    /// Packs interleaved decoder output into a deinterleaved float PCM buffer
    /// matching `format`. Returns nil when the sample count does not fill whole
    /// frames or allocation fails.
    public static func makeBuffer(
        samples: [Float],
        sourceChannelCount: Int,
        downmixToMono: Bool,
        format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard sourceChannelCount > 0, samples.count % sourceChannelCount == 0 else {
            return nil
        }
        let payload = downmixToMono
            ? monoDownmix(samples, channelCount: sourceChannelCount)
            : samples
        let channelCount = downmixToMono ? 1 : sourceChannelCount
        guard Int(format.channelCount) == channelCount else { return nil }
        let frameCount = payload.count / channelCount
        guard
            frameCount > 0,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            ),
            let channels = buffer.floatChannelData
        else { return nil }
        for channel in 0 ..< channelCount {
            for frame in 0 ..< frameCount {
                channels[channel][frame] = payload[frame * channelCount + channel]
            }
        }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }
}
