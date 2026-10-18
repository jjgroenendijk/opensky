// GPU memory in a benchmark result: the peak of each field over the run, and
// the value at its end. See docs/tools/benchmark.md.

import Foundation
import OpenSkyRendering

/// GPU memory at one moment, in MiB.
nonisolated public struct BenchmarkGPUMemorySample: Codable, Equatable, Sendable {
    public let totalMB: Double
    public let renderTargetMB: Double
    public let textureMB: Double

    public init(totalMB: Double, renderTargetMB: Double, textureMB: Double) {
        self.totalMB = totalMB
        self.renderTargetMB = renderTargetMB
        self.textureMB = textureMB
    }

    public init(_ usage: GPUMemoryUsage) {
        let mebibyte = Double(1 << 20)
        self.init(
            totalMB: Double(usage.totalBytes) / mebibyte,
            renderTargetMB: Double(usage.renderTargetBytes) / mebibyte,
            textureMB: Double(usage.textureBytes) / mebibyte
        )
    }
}

/// The peak of each field over the run, and the value at its end.
nonisolated public struct BenchmarkGPUMemory: Codable, Equatable, Sendable {
    public let peak: BenchmarkGPUMemorySample
    public let last: BenchmarkGPUMemorySample

    public init(peak: BenchmarkGPUMemorySample, last: BenchmarkGPUMemorySample) {
        self.peak = peak
        self.last = last
    }
}
