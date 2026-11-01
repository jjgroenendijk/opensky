// GPU memory in a benchmark result, the peak of each field over the run and the
// value at its end, and the frames that left no GPU time. See docs/tools/benchmark.md.

import Foundation
import OpenSkyRendering

/// GPU memory at one moment, in MiB. The fields after `textureMB` are nil in older results.
nonisolated public struct BenchmarkGPUMemorySample: Codable, Equatable, Sendable {
    public var totalMB: Double
    public var renderTargetMB: Double
    public var textureMB: Double
    public var bufferMB: Double?
    public var residentCount: Int?
    /// The app's physical footprint, CPU memory included.
    public var processMB: Double?
    /// The streamed textures' heap pool and the part of it their mapped tiles use.
    public var streamedReservedMB: Double?
    public var streamedUsedMB: Double?
    public var streamedTextures: Int?
    /// Entries in the cell builder's caches.
    public var cachedTextures: Int?
    public var cachedModels: Int?

    public init(totalMB: Double, renderTargetMB: Double, textureMB: Double) {
        self.totalMB = totalMB
        self.renderTargetMB = renderTargetMB
        self.textureMB = textureMB
    }

    public init(_ usage: GPUMemoryUsage) {
        func mebibytes(_ bytes: Int) -> Double {
            Double(bytes) / Double(1 << 20)
        }
        self.init(
            totalMB: mebibytes(usage.totalBytes),
            renderTargetMB: mebibytes(usage.renderTargetBytes),
            textureMB: mebibytes(usage.textureBytes)
        )
        bufferMB = mebibytes(usage.bufferBytes)
        residentCount = usage.residentCount
        processMB = usage.processBytes > 0 ? mebibytes(usage.processBytes) : nil
        streamedReservedMB = mebibytes(usage.streamedReservedBytes)
        streamedUsedMB = mebibytes(usage.streamedUsedBytes)
        streamedTextures = usage.streamedTextures
        cachedTextures = usage.cachedTextures
        cachedModels = usage.cachedModels
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

/// Frames that left no GPU time, so a scene without GPU time says why.
nonisolated public struct BenchmarkGPUFaults: Codable, Equatable, Sendable {
    /// Command buffers whose commit feedback carried an error.
    public var failedCommits = 0
    public var lastFailure: String?
    /// Frames not encoded because the GPU had not finished the slot's last frame.
    public var skippedFrames = 0

    public init(failedCommits: Int = 0, lastFailure: String? = nil, skippedFrames: Int = 0) {
        self.failedCommits = failedCommits
        self.lastFailure = lastFailure
        self.skippedFrames = skippedFrames
    }

    mutating func add(_ report: GPUFrameReport) {
        failedCommits += report.failedCommits
        lastFailure = report.lastFailure ?? lastFailure
        skippedFrames += report.skippedFrames
    }
}
