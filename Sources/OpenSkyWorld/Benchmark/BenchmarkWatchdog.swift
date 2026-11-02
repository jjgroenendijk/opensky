// Ends a launched tour that stopped moving, such as when the Mac sleeps and the
// frame loop stops, so a hidden run cannot wait forever (docs/tools/benchmark.md).

nonisolated public struct BenchmarkWatchdog: Sendable {
    public static let checkIntervalSeconds = 10.0
    /// The first frame of the tour must come within this time of the launch.
    public static let startLimitSeconds = 600.0
    /// The arrival limit of a scene is 150 s, so a healthy tour never comes near this.
    public static let stallLimitSeconds = 240.0

    private let launched: Double
    private var lastProgress: Double?
    private var lastFrameCount = 0
    private var lastCheck: Double

    public init(now: Double) {
        launched = now
        lastCheck = now
    }

    /// Nil while the run moves; otherwise the reason to end it.
    public mutating func check(frameCount: Int, now: Double) -> String? {
        // A late check means the main thread was busy, and a busy thread is not a stall.
        let late = now - lastCheck > 2 * Self.checkIntervalSeconds
        lastCheck = now
        if frameCount != lastFrameCount || (late && lastProgress != nil) {
            lastFrameCount = frameCount
            lastProgress = now
            return nil
        }
        guard let lastProgress else {
            let limit = Self.startLimitSeconds
            return now - launched > limit ? "the tour did not start in \(Int(limit)) s" : nil
        }
        let limit = Self.stallLimitSeconds
        return now - lastProgress > limit ? "no frame for \(Int(limit)) s" : nil
    }
}
