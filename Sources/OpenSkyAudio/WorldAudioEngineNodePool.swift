// Reuses positional player nodes for one-shot buffers, such as footsteps. Attaching,
// connecting, starting, and stopping a node each wait on the audio device, so a crowd's
// footsteps built and dropped one node per step and stalled the frame.

import AVFAudio
import Foundation

/// Idle positional player nodes, by buffer format. Each stays attached, connected to the
/// environment node, and playing, so a new buffer starts with one `scheduleBuffer` call.
@MainActor
struct AudioBufferNodePool {
    /// Idle nodes past this are released; they still render silence each cycle.
    static let capacity = 24

    private var idle: [FormatKey: [AVAudioPlayerNode]] = [:]
    private(set) var idleCount = 0

    struct FormatKey: Hashable {
        let sampleRate: Double
        let channels: AVAudioChannelCount
        let commonFormat: AVAudioCommonFormat
        let interleaved: Bool

        init(_ format: AVAudioFormat) {
            sampleRate = format.sampleRate
            channels = format.channelCount
            commonFormat = format.commonFormat
            interleaved = format.isInterleaved
        }
    }

    mutating func take(format: AVAudioFormat) -> AVAudioPlayerNode? {
        let key = FormatKey(format)
        guard let node = idle[key]?.popLast() else { return nil }
        idleCount -= 1
        return node
    }

    /// False when the pool is full; the caller then releases the node itself.
    mutating func give(_ node: AVAudioPlayerNode, format: AVAudioFormat) -> Bool {
        guard idleCount < Self.capacity else { return false }
        idle[FormatKey(format), default: []].append(node)
        idleCount += 1
        return true
    }

    mutating func drain() -> [AVAudioPlayerNode] {
        defer {
            idle = [:]
            idleCount = 0
        }
        return idle.values.flatMap(\.self)
    }
}

extension WorldAudioEngine {
    /// A playing node for a one-shot buffer: an idle pooled one, or a new one that
    /// joins the pool when its source ends. Interrupting cuts a buffer still sounding
    /// on a node that was evicted.
    func startPooledBuffer(
        _ buffer: AVAudioPCMBuffer,
        request: AudioPlayRequest,
        finished: @escaping @Sendable () -> Void
    ) -> AVAudioPlayerNode {
        makeRoomForNewSource()
        if let node = bufferNodePool.take(format: buffer.format) {
            configure(node, for: request)
            node.scheduleBuffer(buffer, at: nil, options: .interrupts) { finished() }
            return node
        }
        let node = makePositionalNode(request: request, format: buffer.format)
        node.scheduleBuffer(buffer, at: nil, options: []) { finished() }
        node.play()
        return node
    }

    /// Hands a pooled source's node back without stopping it. Silenced, because an
    /// evicted buffer plays on until the node's next buffer interrupts it.
    func recycle(_ source: ActiveAudioSource) {
        source.node.volume = 0
        let format = source.node.outputFormat(forBus: 0)
        guard !bufferNodePool.give(source.node, format: format) else { return }
        source.node.stop()
        engine.detach(source.node)
    }

    /// Stops and detaches every idle pooled node, as when the engine stops.
    func releasePooledNodes() {
        for node in bufferNodePool.drain() {
            node.stop()
            engine.detach(node)
        }
    }
}
