public import Foundation

/// The app's own start, from the process start until the tour starts.
nonisolated public struct BenchmarkAppStart: Codable, Equatable, Sendable {
    /// From the kernel's process start until the world is ready and the tour starts.
    public var processToWorldReadyMS: Double?
    public var worldLoadMS: Double
    /// Each world load stage; they overlap, so they sum to more than `worldLoadMS`.
    public var stages: [String: Double]
    /// Renderer setup, game systems, and the first frame, after the load.
    public var sessionStart: [String: Double]

    public init(
        processToWorldReadyMS: Double?, worldLoadMS: Double,
        stages: [String: Double], sessionStart: [String: Double]
    ) {
        self.processToWorldReadyMS = processToWorldReadyMS
        self.worldLoadMS = worldLoadMS
        self.stages = stages
        self.sessionStart = sessionStart
    }

    /// When the kernel started this process.
    public static func processStart() -> Date? {
        var info = unsafe kinfo_proc()
        var size = unsafe MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard unsafe sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let started = unsafe info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1e6)
    }
}
