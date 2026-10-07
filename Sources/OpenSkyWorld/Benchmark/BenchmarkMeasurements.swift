// The optional sections of the shared benchmark result: GPU time, GPU memory,
// grass, the launch mode, and the route mode. Each is optional, so a result
// written before a section existed still decodes. See docs/tools/benchmark.md.

import Foundation
import OpenSkyRendering

/// Statistics over a list of per-frame times, in milliseconds.
nonisolated public struct BenchmarkTimeStats: Codable, Equatable, Sendable {
    public let frames: Int
    public let averageMS: Double
    public let percentile95MS: Double
    public let worstMS: Double

    public init(frames: Int, averageMS: Double, percentile95MS: Double, worstMS: Double) {
        self.frames = frames
        self.averageMS = averageMS
        self.percentile95MS = percentile95MS
        self.worstMS = worstMS
    }

    /// Nil for an empty list, so a run without samples reports no numbers.
    public init?(milliseconds values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((0.95 * Double(sorted.count)).rounded(.up))
        self.init(
            frames: values.count,
            averageMS: values.reduce(0, +) / Double(values.count),
            percentile95MS: sorted[min(max(rank - 1, 0), sorted.count - 1)],
            worstMS: sorted[sorted.count - 1]
        )
    }
}

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

/// Grass in the measured view's last frame. Zero draws means the view shows no grass.
nonisolated public struct BenchmarkGrass: Codable, Equatable, Sendable {
    public let sceneInstances: Int
    public let drawCalls: Int
    public let drawnInstances: Int

    public init(sceneInstances: Int, drawCalls: Int, drawnInstances: Int) {
        self.sceneInstances = sceneInstances
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
    }

    public init(_ stats: GrassDrawStats) {
        self.init(
            sceneInstances: stats.sceneInstances,
            drawCalls: stats.drawCalls,
            drawnInstances: stats.drawnInstances
        )
    }
}

/// The start of a fresh process: the cold load, then the first frames on the view.
nonisolated public struct BenchmarkLaunch: Codable, Equatable, Sendable {
    /// From the process start to the end of the first drawn frame.
    public let processToFirstFrameMS: Double
    /// The first frame alone; pipeline creation and first uploads land here.
    public let firstFrameMS: Double
    /// How long frames ran after the first frame.
    public let seconds: Double
    /// Every frame in `seconds`, the first one included.
    public let frameTime: BenchmarkTimeStats

    public init(
        processToFirstFrameMS: Double,
        firstFrameMS: Double,
        seconds: Double,
        frameTime: BenchmarkTimeStats
    ) {
        self.processToFirstFrameMS = processToFirstFrameMS
        self.firstFrameMS = firstFrameMS
        self.seconds = seconds
        self.frameTime = frameTime
    }
}

/// The walk route with live streaming and a door, from fresh OpenSky caches.
nonisolated public struct BenchmarkRoute: Codable, Equatable, Sendable {
    /// Every frame of the route, so the worst frame is the worst frame while streaming.
    public let frameTime: BenchmarkTimeStats
    public let gpuTime: BenchmarkTimeStats?
    /// Each cell, distant LOD, and door build, in the order they finished.
    public let cellLoads: [BenchmarkCellLoad]

    public init(
        frameTime: BenchmarkTimeStats,
        gpuTime: BenchmarkTimeStats?,
        cellLoads: [BenchmarkCellLoad]
    ) {
        self.frameTime = frameTime
        self.gpuTime = gpuTime
        self.cellLoads = cellLoads
    }

    public var cellLoadTime: BenchmarkTimeStats? {
        BenchmarkTimeStats(milliseconds: cellLoads.map(\.totalMS))
    }
}

/// The renderer's pipeline setup: its time, and how many pipelines came from the
/// archive an earlier run saved.
nonisolated public struct BenchmarkPipelines: Codable, Equatable, Sendable {
    /// The renderer's setup, pipeline creation included.
    public let rendererSetupMS: Double
    /// `none`, `missing`, `loaded`, or `unreadable`.
    public let archive: String
    public let loaded: Int
    public let compiled: Int
    public let saved: Bool

    public init(rendererSetupMS: Double, stats: PipelineCacheStats) {
        self.rendererSetupMS = rendererSetupMS
        archive = switch stats.archive {
        case .none: "none"
        case .missing: "missing"
        case .loaded: "loaded"
        case .unreadable: "unreadable"
        }
        loaded = stats.hits
        compiled = stats.misses
        saved = stats.saved
    }
}

/// Texture streaming at the end of the run. Set by `benchmark --texture-streaming`.
nonisolated public struct BenchmarkTextureStreaming: Codable, Equatable, Sendable {
    public let streamedTextures: Int
    public let reservedMB: Double
    public let usedMB: Double
    public let budgetMB: Double
    public let levelsLoaded: Int
    public let levelsDropped: Int

    public init(stats: TextureStreamingStats) {
        let mebibyte = Double(1 << 20)
        streamedTextures = stats.streamedTextures
        reservedMB = Double(stats.reservedBytes) / mebibyte
        usedMB = Double(stats.usedBytes) / mebibyte
        budgetMB = Double(stats.budgetBytes) / mebibyte
        levelsLoaded = stats.levelsLoaded
        levelsDropped = stats.levelsDropped
    }
}
