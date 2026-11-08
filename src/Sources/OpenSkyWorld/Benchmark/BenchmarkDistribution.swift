// Statistics over per-frame times. The 1% low is the frame rate of the slowest
// 1% of frames, the number players compare to judge stutter.

import Foundation

nonisolated public struct BenchmarkDistribution: Codable, Equatable, Sendable {
    public let frames: Int
    public let averageMS: Double
    public let percentile50MS: Double
    public let percentile95MS: Double
    public let percentile99MS: Double
    public let worstMS: Double
    /// Frames per second from the average frame time.
    public let averageFPS: Double
    /// Frames per second over the slowest 1% of frames, at least one frame.
    public let onePercentLowFPS: Double

    /// Nil for an empty list, so a scene without samples reports no numbers.
    public init?(milliseconds values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let average = values.reduce(0, +) / Double(values.count)
        frames = values.count
        averageMS = average
        percentile50MS = Self.percentile(50, of: sorted)
        percentile95MS = Self.percentile(95, of: sorted)
        percentile99MS = Self.percentile(99, of: sorted)
        worstMS = sorted[sorted.count - 1]
        averageFPS = average > 0 ? 1000 / average : 0
        let slowest = sorted.suffix(max(sorted.count / 100, 1))
        let slowAverage = slowest.reduce(0, +) / Double(slowest.count)
        onePercentLowFPS = slowAverage > 0 ? 1000 / slowAverage : 0
    }

    /// Nearest rank: the smallest value with at least `percent` of the values at or below it.
    static func percentile(_ percent: Double, of sorted: [Double]) -> Double {
        let rank = Int((percent / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }
}

/// The average and the worst of one per-frame quantity, such as a CPU subsystem.
nonisolated public struct BenchmarkSpread: Codable, Equatable, Sendable {
    public let averageMS: Double
    public let percentile95MS: Double
    public let worstMS: Double

    public init?(milliseconds values: [Double]) {
        guard let distribution = BenchmarkDistribution(milliseconds: values) else { return nil }
        averageMS = distribution.averageMS
        percentile95MS = distribution.percentile95MS
        worstMS = distribution.worstMS
    }
}
