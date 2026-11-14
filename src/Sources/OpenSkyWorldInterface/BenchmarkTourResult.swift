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
    /// `processToWorldReadyMS` cut at each start step, by `AppStartPhase` name. The
    /// phases follow each other, so they add up to the whole time.
    public var phases: [String: Double]

    public init(
        processToWorldReadyMS: Double?, worldLoadMS: Double,
        stages: [String: Double], sessionStart: [String: Double],
        phases: [String: Double] = [:]
    ) {
        self.processToWorldReadyMS = processToWorldReadyMS
        self.worldLoadMS = worldLoadMS
        self.stages = stages
        self.sessionStart = sessionStart
        self.phases = phases
    }

    private enum CodingKeys: String, CodingKey {
        case processToWorldReadyMS, worldLoadMS, stages, sessionStart, phases
    }

    /// A result from before the phases has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        processToWorldReadyMS = try container.decodeIfPresent(
            Double.self, forKey: .processToWorldReadyMS
        )
        worldLoadMS = try container.decode(Double.self, forKey: .worldLoadMS)
        stages = try container.decode([String: Double].self, forKey: .stages)
        sessionStart = try container.decode([String: Double].self, forKey: .sessionStart)
        phases = try container.decodeIfPresent([String: Double].self, forKey: .phases) ?? [:]
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
