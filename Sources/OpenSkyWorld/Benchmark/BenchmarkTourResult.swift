// The stable output of one benchmark tour. The CLI, the launcher, and the
// Diagnostics page read this one shape. See docs/tools/benchmark.md.

import Darwin
import Foundation
import OpenSkyCells
import OpenSkyGameData
import OpenSkyLoading

nonisolated public enum BenchmarkSceneStatus: String, Codable, Sendable {
    case measured
    /// The scene needs a plugin the load order lacks.
    case skipped
    /// The scene did not arrive or measured no frames.
    case failed
}

nonisolated public struct BenchmarkSceneResult: Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let group: BenchmarkSceneGroup
    public let shot: String
    public let place: String
    public var status: BenchmarkSceneStatus
    public var note: String?
    public var hour: Float?
    public var weather: String?
    /// From the teleport to the end of streaming.
    public var arrivalMS: Double?
    /// The arrival's cell builds split into asset phases; nil when no recorder was attached.
    public var arrivalPhases: LoadPhaseTimes?
    public var frameTime: BenchmarkDistribution?
    public var gpuTime: BenchmarkDistribution?
    /// GPU time per render pass, keyed by `GPUPass`.
    public var passes: [String: BenchmarkSpread] = [:]
    /// CPU time per subsystem, keyed by `BenchmarkCPUProbe`.
    public var cpu: [String: BenchmarkSpread] = [:]
    public var averageDrawCalls: Int?
    public var averageDrawnInstances: Int?
    public var gpuMemory: BenchmarkGPUMemory?
    public var capturePath: String?

    public init(scene: BenchmarkScene, status: BenchmarkSceneStatus, note: String? = nil) {
        id = scene.id
        title = scene.title
        group = scene.group
        shot = scene.shot.kind
        place = scene.place.label
        self.status = status
        self.note = note
    }

    /// The pass with the largest average GPU time.
    public var slowestPass: (name: String, averageMS: Double)? {
        passes.max { $0.value.averageMS < $1.value.averageMS }
            .map { (name: $0.key, averageMS: $0.value.averageMS) }
    }
}

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
        report: WorldLoadReport,
        session: SessionStartTiming,
        processToWorldReadyMS: Double?
    ) {
        worldLoadMS = report.total.milliseconds
        stages = Dictionary(
            report.timeline.slowestFirst.map { ($0.stage.rawValue, $0.duration.milliseconds) },
            uniquingKeysWith: +
        )
        sessionStart = Dictionary(
            session.measured.map { ($0.phase.rawValue, $0.duration.milliseconds) },
            uniquingKeysWith: +
        )
        self.processToWorldReadyMS = processToWorldReadyMS
    }

    /// When the kernel started this process.
    public static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(started.tv_sec) + Double(started.tv_usec) / 1e6)
    }
}

nonisolated public struct BenchmarkTourResult: Codable, Equatable, Sendable {
    /// 2: the tour. 1 was the single-view benchmark this replaced.
    public static let currentSchemaVersion = 2

    public var schemaVersion = Self.currentSchemaVersion
    public var startedAt: Date
    public var durationSeconds: Double = 0
    public var machine: BenchmarkMachine
    public var buildConfiguration: BenchmarkBuildConfiguration
    public var preset: BenchmarkPreset
    public var frameWidth = 0
    public var frameHeight = 0
    /// Every setting that differs from its default during the run, overrides included.
    public var settings: [String: Double] = [:]
    public var overrides: [String: Double] = [:]
    public var passTiming = false
    public var appStart: BenchmarkAppStart?
    public var coldLoad: BenchmarkLoadPass?
    public var warmLoad: BenchmarkLoadPass?
    public var scenes: [BenchmarkSceneResult] = []
    /// Every measured frame of every scene.
    public var frameTime: BenchmarkDistribution?
    public var gpuTime: BenchmarkDistribution?
    public var gpuMemory: BenchmarkGPUMemory?
    /// True when the user stopped the tour before its last scene.
    public var stopped = false

    public init(
        startedAt: Date, machine: BenchmarkMachine,
        buildConfiguration: BenchmarkBuildConfiguration = .current, preset: BenchmarkPreset
    ) {
        self.startedAt = startedAt
        self.machine = machine
        self.buildConfiguration = buildConfiguration
        self.preset = preset
    }

    /// No scene failed and every load built, so the numbers compare with another clean run.
    public var isComparable: Bool {
        !stopped && scenes.allSatisfy { $0.status != .failed }
            && ((coldLoad?.cells ?? []) + (warmLoad?.cells ?? [])).allSatisfy { $0.error == nil }
    }

    /// Pretty, key-sorted JSON with ISO 8601 dates, so two results diff line by line.
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(json: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Self.self, from: json)
    }
}

extension Duration {
    nonisolated var milliseconds: Double {
        let parts = components
        return Double(parts.seconds) * 1000 + Double(parts.attoseconds) / 1e15
    }
}
