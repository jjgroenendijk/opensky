// GPU time per pass, from Metal 4 timestamp counter heaps. Each mark ends the pass
// before it. Apple GPUs run one render encoder's draws together per tile, so the
// marks sit between encoders only (docs/tools/benchmark.md).

import Metal

/// The passes in frame order. A pass that a frame skips takes no time.
nonisolated public enum GPUPass: String, CaseIterable, Codable, Sendable {
    /// Texture streaming and the ray-traced shadow build.
    case setup
    case shadows
    /// The main render pass: the world, effects, image space, upscaling, and the overlays.
    case scene
}

public final class GPUPassTimer {
    /// The frame start plus one mark per pass, with room for a repeated mark.
    static let entriesPerSlot = GPUPass.allCases.count * 2 + 1

    private let heaps: [any MTL4CounterHeap]
    private let ticksPerMS: Double
    /// The marks written into each slot's heap, in order, and the frame they belong to.
    private var marks: [[GPUPass]]
    private var slotFrames: [Int?]
    private var slot = 0
    private var completed: [[GPUPass: Double]] = []

    public init?(device: any MTLDevice, slots: Int) {
        let descriptor = MTL4CounterHeapDescriptor()
        descriptor.type = .timestamp
        descriptor.count = Self.entriesPerSlot
        var heaps: [any MTL4CounterHeap] = []
        for _ in 0 ..< slots {
            guard let heap = try? device.makeCounterHeap(descriptor: descriptor) else { return nil }
            heap.label = "GPU Pass Timer"
            heaps.append(heap)
        }
        let frequency = device.queryTimestampFrequency()
        guard frequency > 0 else { return nil }
        self.heaps = heaps
        ticksPerMS = Double(frequency) / 1000
        marks = Array(repeating: [], count: slots)
        slotFrames = Array(repeating: nil, count: slots)
    }

    /// Reads the slot's last frame once `completedFrame` says the GPU finished it, then
    /// writes this frame's start mark.
    func beginFrame(
        slot: Int, frame: Int, completedFrame: Int, commandBuffer: any MTL4CommandBuffer
    ) {
        self.slot = slot
        if let previous = slotFrames[slot], previous <= completedFrame {
            resolve(slot: slot)
        }
        heaps[slot].invalidateCounterRange(0 ..< Self.entriesPerSlot)
        marks[slot] = []
        slotFrames[slot] = frame
        commandBuffer.writeTimestamp(counterHeap: heaps[slot], index: 0)
    }

    /// Ends `pass` between two encoders.
    func mark(_ pass: GPUPass, commandBuffer: any MTL4CommandBuffer) {
        guard let index = nextIndex(for: pass) else { return }
        commandBuffer.writeTimestamp(counterHeap: heaps[slot], index: index)
    }

    /// Per-pass milliseconds of each frame the GPU finished since the last call.
    public func take() -> [[GPUPass: Double]] {
        defer { completed = [] }
        return completed
    }

    private func nextIndex(for pass: GPUPass) -> Int? {
        guard slotFrames[slot] != nil, marks[slot].count + 1 < Self.entriesPerSlot else {
            return nil
        }
        marks[slot].append(pass)
        return marks[slot].count
    }

    private func resolve(slot: Int) {
        let count = marks[slot].count + 1
        defer { slotFrames[slot] = nil }
        guard
            count > 1,
            let data = try? heaps[slot].resolveCounterRange(0 ..< count),
            data.count >= count * MemoryLayout<UInt64>.stride
        else { return }
        let ticks = data.withUnsafeBytes { Array($0.bindMemory(to: UInt64.self).prefix(count)) }
        var frame: [GPUPass: Double] = [:]
        // A counter the GPU never wrote reads zero, so a pair with one is skipped.
        for (index, pass) in marks[slot].enumerated()
            where ticks[index] != 0 && ticks[index + 1] >= ticks[index]
        {
            frame[pass, default: 0] += Double(ticks[index + 1] - ticks[index]) / ticksPerMS
        }
        completed.append(frame)
    }
}

extension Renderer {
    /// Starts or stops pass timing; the first frames after a start have no samples yet.
    public func setPassTimingEnabled(_ enabled: Bool) {
        passTimer = enabled ? passTimer ?? GPUPassTimer(
            device: device, slots: Self.maxFramesInFlight
        ) : nil
    }
}
