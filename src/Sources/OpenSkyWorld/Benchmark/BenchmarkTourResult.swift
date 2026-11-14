// The stable output of one benchmark tour. The CLI, the launcher, and the
// Diagnostics page read this one shape. See docs/tools/benchmark.md.

import Darwin
public import Foundation
import OpenSkyCells
public import OpenSkyGameData
import OpenSkyLoading
public import OpenSkyWorldInterface

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
    let group: BenchmarkSceneGroup
    let shot: String
    let place: String
    public var status: BenchmarkSceneStatus
    var note: String?
    var hour: Float?
    var weather: String?
    /// From the teleport to the end of streaming.
    var arrivalMS: Double?
    /// The arrival's cell builds split into asset phases; nil when no recorder was attached.
    var arrivalPhases: LoadPhaseTimes?
    public var frameTime: BenchmarkDistribution?
    var gpuTime: BenchmarkDistribution?
    /// GPU time per render pass, keyed by `GPUPass`.
    var passes: [String: BenchmarkSpread] = [:]
    /// CPU time per subsystem, keyed by `BenchmarkCPUProbe`.
    var cpu: [String: BenchmarkSpread] = [:]
    var averageDrawCalls: Int?
    var averageDrawnInstances: Int?
    var gpuMemory: BenchmarkGPUMemory?
    /// Nil when every frame was encoded and every command buffer finished without error.
    var gpuFaults: BenchmarkGPUFaults?
    var capturePath: String?
    /// The PNGs of the start, middle, and end of the shot, when the run saved them.
    var screenshots: [String]?

    init(scene: BenchmarkScene, status: BenchmarkSceneStatus, note: String? = nil) {
        id = scene.id
        title = scene.title
        group = scene.group
        shot = scene.shot.kind
        place = scene.place.label
        self.status = status
        self.note = note
    }

    /// The pass with the largest average GPU time.
    var slowestPass: (name: String, averageMS: Double)? {
        passes.max { $0.value.averageMS < $1.value.averageMS }
            .map { (name: $0.key, averageMS: $0.value.averageMS) }
    }
}

nonisolated public struct BenchmarkTourResult: Codable, Equatable, Sendable {
    /// 2: the tour. 1 was the single-view benchmark this replaced.
    static let currentSchemaVersion = 2

    var schemaVersion = Self.currentSchemaVersion
    public var startedAt: Date
    public var durationSeconds: Double = 0
    public var machine: BenchmarkMachine
    public var buildConfiguration: BenchmarkBuildConfiguration
    public var preset: BenchmarkPreset
    public var frameWidth = 0
    public var frameHeight = 0
    /// Nil in a result from before hidden runs existed.
    public var display: BenchmarkDisplay?
    /// The audio update is a measured CPU phase, so a muted run says so.
    public var audioMuted: Bool?
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
    var gpuTime: BenchmarkDistribution?
    var gpuMemory: BenchmarkGPUMemory?
    /// True when the user stopped the tour before its last scene.
    public var stopped = false
    /// Writing a PNG takes main-actor time inside the measured frames.
    public var screenshots = false

    public init(
        startedAt: Date, machine: BenchmarkMachine,
        buildConfiguration: BenchmarkBuildConfiguration = .current, preset: BenchmarkPreset
    ) {
        self.startedAt = startedAt
        self.machine = machine
        self.buildConfiguration = buildConfiguration
        self.preset = preset
    }

    /// No scene failed, every load built, and no PNG was written, so the numbers compare.
    public var isComparable: Bool {
        !stopped && !screenshots && scenes.allSatisfy { $0.status != .failed }
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

extension BenchmarkAppStart {
    /// `processStart` is nil when the kernel did not say; the phases are then left out.
    public init(
        report: WorldLoadReport,
        session: SessionStartTiming,
        processStart: Date?,
        worldReady: Date
    ) {
        let marks = report.marks
        let ends: [AppStartPhase: Date] = [
            .beforeMain: marks.mainEntered, .appLaunch: marks.launchFinished,
            .beforeWorldLoad: marks.worldLoadStarted, .worldLoad: marks.worldLoadFinished,
            .beforeSession: session.startedAt, .session: session.firstFrameAt
        ].compactMapValues(\.self)
        let phases = processStart.map {
            AppStartPhase.split(from: $0, to: worldReady, ends: ends)
        } ?? [:]
        self.init(
            processToWorldReadyMS: processStart.map {
                worldReady.timeIntervalSince($0) * Self.millisecondsPerSecond
            },
            worldLoadMS: report.total.milliseconds,
            stages: Dictionary(
                report.timeline.slowestFirst.map { ($0.stage.rawValue, $0.duration.milliseconds) },
                uniquingKeysWith: +
            ),
            sessionStart: Dictionary(
                session.measured.map { ($0.phase.rawValue, $0.duration.milliseconds) },
                uniquingKeysWith: +
            ),
            phases: Dictionary(uniqueKeysWithValues: phases.map { ($0.key.rawValue, $0.value) })
        )
    }

    private static let millisecondsPerSecond = 1000.0
}
