// The fixed inputs and the stable output of the shared performance benchmark.
// The CLI, the graphics presets, and the Diagnostics page all read this one
// shape. See docs/tools/benchmark.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

/// One exterior grid slot, in a form that encodes as plain numbers.
nonisolated public struct BenchmarkGridCell: Codable, Equatable, Sendable {
    public let x: Int32
    public let y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
}

/// A level camera at eye height over the terrain, looking toward a point in the world.
nonisolated public struct BenchmarkView: Codable, Equatable, Sendable {
    public let fromX: Float
    public let fromY: Float
    public let towardX: Float
    public let towardY: Float
    public let eyeHeight: Float

    public init(fromX: Float, fromY: Float, towardX: Float, towardY: Float, eyeHeight: Float) {
        self.fromX = fromX
        self.fromY = fromY
        self.towardX = towardX
        self.towardY = towardY
        self.eyeHeight = eyeHeight
    }
}

/// What the benchmark loads and renders. Every run of `standard` uses the same cells and view.
nonisolated public struct PerformanceBenchmarkPlan: Codable, Equatable, Sendable {
    public let worldspace: String
    /// The center of the exterior block; distant LOD is built around it.
    public let centerCell: BenchmarkGridCell
    public let exteriorCells: [BenchmarkGridCell]
    public let interiorCellFormIDs: [UInt32]
    public let view: BenchmarkView
    public let frameWidth: Int
    public let frameHeight: Int
    /// Frames rendered before measuring, so pipeline creation and first uploads do not count.
    public let warmupFrames: Int
    public let measuredFrames: Int

    /// Whiterun's plain: the first-render cell with its eight neighbors, then the farmhouse
    /// interior the walk benchmark also enters. The view looks along the walk route.
    public static let standard = Self(
        worldspace: FirstRenderCell.worldspaceEditorID,
        centerCell: BenchmarkGridCell(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
        exteriorCells: (-1 ... 1).flatMap { dy in
            (-1 ... 1).map { dx in
                BenchmarkGridCell(x: FirstRenderCell.gridX + dx, y: FirstRenderCell.gridY + dy)
            }
        },
        interiorCellFormIDs: [WalkPathRoute.farmInterior.rawValue],
        view: BenchmarkView(
            fromX: WalkPathRoute.exteriorWaypoints[0].x,
            fromY: WalkPathRoute.exteriorWaypoints[0].y,
            towardX: WalkPathRoute.exteriorReturn.x,
            towardY: WalkPathRoute.exteriorReturn.y,
            eyeHeight: PlayerCapsule.standard.eyeHeight
        ),
        frameWidth: 2560,
        frameHeight: 1600,
        warmupFrames: 60,
        measuredFrames: 600
    )

    /// The same cells and view at another frame size.
    public func resized(width: Int, height: Int) -> Self {
        Self(
            worldspace: worldspace,
            centerCell: centerCell,
            exteriorCells: exteriorCells,
            interiorCellFormIDs: interiorCellFormIDs,
            view: view,
            frameWidth: width,
            frameHeight: height,
            warmupFrames: warmupFrames,
            measuredFrames: measuredFrames
        )
    }
}

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

/// One pass over every plan cell. Cold starts from empty caches; warm reuses them.
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

nonisolated public struct BenchmarkFrameTime: Codable, Equatable, Sendable {
    public let frames: Int
    public let averageMS: Double
    public let percentile95MS: Double
    public let worstMS: Double
    /// The last frame's draw counts. Two runs with different counts drew different views.
    public let drawCalls: Int
    public let drawnInstances: Int
    /// GPU time per frame, from the command buffer's GPU start and end times.
    public let gpuTime: BenchmarkTimeStats?
    public let grass: BenchmarkGrass?
    /// CPU time of the shadow and scene pass encoding per frame.
    public var encodeTime: BenchmarkTimeStats?
    /// Whether the GPU culled the scene's static groups. Nil in older results.
    public var gpuCulling: Bool?
    /// The render scale in percent MetalFX upscaled from; 0 is native. Nil in older results.
    public var renderScale: Int?
    /// `temporal` or `spatial` when `renderScale` is above 0.
    public var upscaler: String?
    /// Whether each frame also built a MetalFX interpolated frame. Nil in older results.
    public var frameInterpolation: Bool?
    /// Whether grass drew through object and mesh shaders. Nil in older results.
    public var meshShaderGrass: Bool?

    public init(
        frames: Int,
        averageMS: Double,
        percentile95MS: Double,
        worstMS: Double,
        drawCalls: Int,
        drawnInstances: Int,
        gpuTime: BenchmarkTimeStats? = nil,
        grass: BenchmarkGrass? = nil
    ) {
        self.frames = frames
        self.averageMS = averageMS
        self.percentile95MS = percentile95MS
        self.worstMS = worstMS
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.gpuTime = gpuTime
        self.grass = grass
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

nonisolated public struct PerformanceBenchmarkResult: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let startedAt: Date
    public let machine: BenchmarkMachine
    public let buildConfiguration: BenchmarkBuildConfiguration
    public let plan: PerformanceBenchmarkPlan
    public let coldLoad: BenchmarkLoadPass
    public let warmLoad: BenchmarkLoadPass
    public let frameTime: BenchmarkFrameTime
    /// Sampled after each load pass and each measured frame.
    public var gpuMemory: BenchmarkGPUMemory?
    /// Set by `benchmark --launch`.
    public var launch: BenchmarkLaunch?
    /// Set by `benchmark --route`.
    public var route: BenchmarkRoute?
    /// The renderer's pipeline setup.
    public var pipelines: BenchmarkPipelines?
    /// Set by `benchmark --texture-streaming`.
    public var textureStreaming: BenchmarkTextureStreaming?

    public init(
        startedAt: Date,
        machine: BenchmarkMachine,
        buildConfiguration: BenchmarkBuildConfiguration,
        plan: PerformanceBenchmarkPlan,
        coldLoad: BenchmarkLoadPass,
        warmLoad: BenchmarkLoadPass,
        frameTime: BenchmarkFrameTime
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.startedAt = startedAt
        self.machine = machine
        self.buildConfiguration = buildConfiguration
        self.plan = plan
        self.coldLoad = coldLoad
        self.warmLoad = warmLoad
        self.frameTime = frameTime
    }

    /// True when every cell built, so the numbers compare with another clean run.
    public var isComparable: Bool {
        (coldLoad.cells + warmLoad.cells + (route?.cellLoads ?? [])).allSatisfy { $0.error == nil }
    }

    /// Pretty, key-sorted JSON with ISO 8601 dates, so two results diff cleanly.
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
