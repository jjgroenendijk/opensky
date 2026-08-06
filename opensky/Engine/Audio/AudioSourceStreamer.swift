// Streaming decode for one playing source: keeps an AVAudioPlayerNode fed with
// short PCM buffers instead of decoding the whole file up front (a music track
// decodes to ~37 MB of PCM; issue #218).
//
// Threading model (docs/engine/audio.md): all decode work and all mutable
// scheduling state live on the shared audio-decode DispatchQueue passed in by
// WorldAudioEngine — including the WMADecoder, which is not Sendable and must be
// owned by exactly one queue. The main actor only creates, starts and stops
// streamers and polls `isFinished`. OpenSky code never runs on the audio render
// thread: AVAudioPlayerNode consumes the scheduled buffers there itself, and its
// completion handlers (fired on an AVFAudio internal queue) immediately hop back
// onto the decode queue. Nothing in this file allocates, locks or logs on the
// render thread because nothing in this file runs there.

import AVFAudio
import Foundation
import Synchronization

nonisolated final class AudioSourceStreamer: @unchecked Sendable {
    /// Encoded packets decoded per scheduled buffer. At vanilla music rates one
    /// packet decodes to ~46 ms of PCM, so a chunk is roughly three quarters of
    /// a second.
    static let packetsPerChunk = 16
    /// Buffers scheduled ahead of playback. Refill triggers when one finishes
    /// playing, so two chunks (~1.5 s) of margin always remain — far more than
    /// the sub-millisecond decode of the next chunk needs.
    static let maxChunksInFlight = 3

    private let queue: DispatchQueue
    private let node: AVAudioPlayerNode
    private let format: AVAudioFormat
    private let file: XWMFile
    private let downmixToMono: Bool
    /// Continuous sources (the per-cell ambient bed) rewind to the first packet
    /// at end of file instead of finishing, so the engine never retires them.
    private let loops: Bool

    // Queue-confined state: touched only on `queue`.
    private var decoder: WMADecoder?
    private var nextPacketIndex = 0
    private var chunksInFlight = 0
    private var drained = false
    private var stopped = false
    /// Whether the current pass over the file has yielded any PCM. A looping
    /// source whose pass decoded nothing ends instead of rewinding, so a file
    /// the decoder cannot use never spins the decode queue forever.
    private var passProducedSamples = false

    /// Cross-thread completion flag, polled by the main actor each audio tick.
    private let finished = Mutex(false)

    var isFinished: Bool {
        finished.withLock { $0 }
    }

    /// - Parameters:
    ///   - file: the framed container; its payload is read packet-by-packet via
    ///     `packet(at:)`, never copied whole.
    ///   - node: the player this streamer feeds. The engine owns attach/detach.
    ///   - format: the node's connection format (mono for positional sources).
    ///   - downmixToMono: averages stereo PCM into one channel so the
    ///     environment node can spatialize it (it passes stereo through flat).
    ///   - loops: rewind to the first packet at end of file instead of
    ///     reporting completion.
    ///   - queue: the engine's shared serial decode queue.
    init(
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

    /// Begins decoding and scheduling on the decode queue. The caller starts
    /// the player node; playback begins when the first buffer lands.
    func start() {
        queue.async { [self] in
            do {
                decoder = try WMADecoder(parameters: AudioCodecParameters(xwm: file.codec))
            } catch {
                markFinished()
                return
            }
            scheduleMore()
        }
    }

    /// Requests a stop. The engine also stops the node on the main actor, which
    /// discards scheduled buffers and fires their completions; this flag stops
    /// the decode queue from scheduling replacements.
    func requestStop() {
        queue.async { [self] in
            stopped = true
            markFinished()
        }
    }

    // MARK: - Decode queue

    private func scheduleMore() {
        while !stopped, !drained, chunksInFlight < Self.maxChunksInFlight {
            guard let samples = decodeNextChunk(), !samples.isEmpty else { continue }
            guard
                let buffer = Self.makeBuffer(
                    samples: samples,
                    sourceChannelCount: file.codec.channelCount,
                    downmixToMono: downmixToMono,
                    format: format
                )
            else {
                drained = true
                break
            }
            chunksInFlight += 1
            // Completion fires on an AVFAudio internal queue -> hop straight
            // back to the decode queue.
            node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
                guard let self else { return }
                queue.async { self.chunkCompleted() }
            }
        }
        if drained, chunksInFlight == 0 {
            markFinished()
        }
    }

    /// Decodes up to `packetsPerChunk` packets. At end of file a looping source
    /// rewinds and any other source sets `drained`. Returns nil after a decode
    /// error (the source ends early but never traps).
    private func decodeNextChunk() -> [Float]? {
        guard let decoder else {
            drained = true
            return nil
        }
        var samples: [Float] = []
        var packetsUsed = 0
        do {
            while packetsUsed < Self.packetsPerChunk {
                guard let packet = file.packet(at: nextPacketIndex) else {
                    let tail = try decoder.flush()
                    append(tail, to: &samples)
                    rewindOrDrain(decoder: decoder)
                    break
                }
                nextPacketIndex += 1
                packetsUsed += 1
                try append(decoder.decode(packet: packet), to: &samples)
            }
        } catch {
            drained = true
            return nil
        }
        return samples
    }

    private func append(_ decoded: [Float], to samples: inout [Float]) {
        guard !decoded.isEmpty else { return }
        passProducedSamples = true
        samples.append(contentsOf: decoded)
    }

    /// End of the packet table. A looping source starts the file over with a
    /// reset decoder; everything else finishes once the scheduled buffers play
    /// out.
    private func rewindOrDrain(decoder: WMADecoder) {
        guard
            Self.shouldRewind(
                loops: loops, passProducedSamples: passProducedSamples, stopped: stopped
            )
        else {
            drained = true
            return
        }
        decoder.reset()
        nextPacketIndex = 0
        passProducedSamples = false
    }

    private func chunkCompleted() {
        chunksInFlight -= 1
        if drained || stopped {
            if chunksInFlight <= 0 {
                markFinished()
            }
            return
        }
        scheduleMore()
    }

    private func markFinished() {
        finished.withLock { $0 = true }
    }

    // MARK: - Policy + PCM packing (pure, unit-tested)

    /// Rewind policy at end of file, kept pure because no WMA fixture may enter
    /// the repository and the decode loop itself can only be exercised against
    /// the user's own install. A source rewinds when it was started as a loop,
    /// its last pass actually produced PCM, and no stop was requested.
    static func shouldRewind(loops: Bool, passProducedSamples: Bool, stopped: Bool) -> Bool {
        loops && passProducedSamples && !stopped
    }

    /// Averages interleaved multi-channel PCM into one mono channel.
    static func monoDownmix(_ interleaved: [Float], channelCount: Int) -> [Float] {
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
    static func makeBuffer(
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
