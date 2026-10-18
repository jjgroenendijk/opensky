// The load-time half of a benchmark result: one pass over a block of cells,
// each cell's time, and the asset phases. Also the build that ran it.

import Foundation
import OpenSkyGameData
import OpenSkyRendering

nonisolated public struct BenchmarkCellLoad: Codable, Equatable, Sendable {
    /// `Tamriel (6,-2)` or `interior 00016204`.
    public let label: String
    public let totalMS: Double
    /// The build error; a failed cell makes the run not comparable.
    public let error: String?

    public init(label: String, totalMS: Double, error: String? = nil) {
        self.label = label
        self.totalMS = totalMS
        self.error = error
    }
}

/// One pass over a block of cells. Cold starts from empty caches; warm reuses them.
nonisolated public struct BenchmarkLoadPass: Codable, Equatable, Sendable {
    public let totalMS: Double
    /// Opening the plugin and the archives; zero for a warm pass.
    public let setupMS: Double
    public let phases: LoadPhaseTimes
    public let cells: [BenchmarkCellLoad]

    public init(
        totalMS: Double,
        setupMS: Double,
        phases: LoadPhaseTimes,
        cells: [BenchmarkCellLoad]
    ) {
        self.totalMS = totalMS
        self.setupMS = setupMS
        self.phases = phases
        self.cells = cells
    }

    /// Phases with `other`, largest first.
    public var rankedPhases: [(name: String, ms: Double)] {
        let named = LoadPhase.allCases.map { (name: $0.rawValue, ms: phases[$0]) }
            + [(name: "other", ms: phases.otherMS)]
        return named.sorted { $0.ms > $1.ms }
    }
}

nonisolated public enum BenchmarkBuildConfiguration: String, Codable, Sendable {
    case debug
    /// Debug with optimization, as the perf test plan builds it.
    case optimizedDebug
    case release

    public static var current: Self {
        #if DEBUG && OPENSKY_OPTIMIZED
            .optimizedDebug
        #elseif DEBUG
            .debug
        #else
            .release
        #endif
    }
}

/// The peak of each memory field over the samples, and the last sample.
nonisolated struct GPUMemoryTracker {
    private var peak = GPUMemoryUsage()
    private var last: GPUMemoryUsage?

    mutating func add(_ usage: GPUMemoryUsage) {
        peak = peak.fieldMaximum(usage)
        last = usage
    }

    var result: BenchmarkGPUMemory? {
        guard let last else { return nil }
        return BenchmarkGPUMemory(
            peak: BenchmarkGPUMemorySample(peak),
            last: BenchmarkGPUMemorySample(last)
        )
    }
}
