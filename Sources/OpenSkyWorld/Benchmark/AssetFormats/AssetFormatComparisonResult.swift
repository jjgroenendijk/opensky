// The stable output of the asset format comparison. Pretty, key-sorted JSON,
// so two runs diff line by line (docs/tools/asset-format-comparison.md).

import Foundation
import OpenSkyRendering

/// Where a measured load reads from.
nonisolated public enum AssetLoadPath: String, Codable, Sendable {
    /// The current engine path: the archive through the file system, then a CPU parse.
    case archive
    /// A cache file read on the CPU, then copied to the GPU or into arrays.
    case cpu
    /// A cache file streamed by Metal fast resource loading into a texture or buffer.
    case mtlio
}

nonisolated public struct AssetLoadTiming: Codable, Equatable, Sendable {
    /// Reading and decompressing. On the `mtlio` path it also holds the GPU copy.
    public let readMS: Double
    /// Parsing or decoding into engine values.
    public let decodeMS: Double
    /// Building GPU resources or engine arrays from the decoded values.
    public let uploadMS: Double

    public init(readMS: Double, decodeMS: Double, uploadMS: Double) {
        self.readMS = readMS
        self.decodeMS = decodeMS
        self.uploadMS = uploadMS
    }

    public var totalMS: Double {
        readMS + decodeMS + uploadMS
    }
}

/// How close a candidate is to the original. `exact` means equal bytes or pixels.
nonisolated public struct AssetFidelity: Codable, Equatable, Sendable {
    public let exact: Bool
    public let image: TextureImageDifference?
    /// Signal-to-noise ratio of decoded audio against the original, in dB.
    public let signalToNoiseDB: Double?

    public init(exact: Bool, image: TextureImageDifference? = nil, signalToNoiseDB: Double? = nil) {
        self.exact = exact
        self.image = image
        self.signalToNoiseDB = signalToNoiseDB
    }

    public static let lossless = Self(exact: true)
}

nonisolated public struct AssetCandidateMeasurement: Codable, Equatable, Sendable {
    /// `original`, `shipped`, `ready`, a texture format, or an audio format.
    public let candidate: String
    /// Nil for the archive path.
    public let storage: AssetFileStorage?
    public let path: AssetLoadPath
    public let timing: AssetLoadTiming
    /// GPU or CPU bytes the loaded asset holds.
    public let memoryBytes: Int
    /// Bytes on disk: the archive entry, or the cache file.
    public let diskBytes: Int
    public let fidelity: AssetFidelity
    /// Time to build the cache payload from the original; zero for the original itself.
    public let convertMS: Double
    public let error: String?

    public init(
        candidate: String,
        storage: AssetFileStorage?,
        path: AssetLoadPath,
        timing: AssetLoadTiming,
        sizes: (memory: Int, disk: Int),
        fidelity: AssetFidelity,
        convertMS: Double = 0,
        error: String? = nil
    ) {
        self.candidate = candidate
        self.storage = storage
        self.path = path
        self.timing = timing
        memoryBytes = sizes.memory
        diskBytes = sizes.disk
        self.fidelity = fidelity
        self.convertMS = convertMS
        self.error = error
    }
}

nonisolated public struct AssetMeasurement: Codable, Equatable, Sendable {
    public let entry: AssetSampleEntry
    /// `2048x2048 bc1, 11 mips` or `2 meshes, 1156 vertices`.
    public let detail: String
    public let candidates: [AssetCandidateMeasurement]
    /// Set when the original could not be loaded; then there are no candidates.
    public let error: String?

    public init(
        entry: AssetSampleEntry,
        detail: String,
        candidates: [AssetCandidateMeasurement],
        error: String? = nil
    ) {
        self.entry = entry
        self.detail = detail
        self.candidates = candidates
        self.error = error
    }
}

nonisolated public enum AssetFormatComparisonResultError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
}

nonisolated public struct AssetFormatComparisonResult: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let startedAt: Date
    public let machine: BenchmarkMachine
    public let buildConfiguration: BenchmarkBuildConfiguration
    /// The 1-minute load average at start and end. Other work on the machine adds noise.
    public let loadAverage: [Double]
    public let plan: AssetFormatComparisonPlan
    public let assets: [AssetMeasurement]
    public let summaries: [AssetFormatSummary]
    public let recommendations: [AssetFormatRecommendation]

    public init(
        startedAt: Date,
        machine: BenchmarkMachine,
        loadAverage: [Double],
        plan: AssetFormatComparisonPlan,
        assets: [AssetMeasurement]
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.startedAt = startedAt
        self.machine = machine
        buildConfiguration = .current
        self.loadAverage = loadAverage
        self.plan = plan
        self.assets = assets
        summaries = AssetFormatSummary.summarize(assets)
        recommendations = AssetFormatRecommendation.recommend(summaries)
    }

    /// True when every sampled asset loaded, so totals compare with another run.
    public var isComparable: Bool {
        assets.allSatisfy { $0.error == nil }
    }

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(json: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(Self.self, from: json)
        guard result.schemaVersion == currentSchemaVersion else {
            throw AssetFormatComparisonResultError.unsupportedSchemaVersion(result.schemaVersion)
        }
        return result
    }
}
