// App side of `BenchmarkTourCoordinator`: the live game window as the tour's
// world. It takes the clock, the camera, and the HUD for the run and gives them
// back at the end. The tour rules live in the coordinator (docs/tools/benchmark.md).

public import Foundation
import Metal
import OpenSkyAgentControl
import OpenSkyCells
import OpenSkyDiagnostics
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyLoading
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyWeather
public import OpenSkyWorld
public import OpenSkyWorldInterface
import QuartzCore
import simd

/// The game window during a tour: its readout, its window mode, and its frame loop.
@MainActor
public protocol BenchmarkViewPort: AnyObject {
    var drawableSize: CGSize { get }
    var isOverlayEnabled: Bool { get set }
    func attachOverlay(enabled: Bool)
    func showOverlay(_ snapshot: BenchmarkTourSnapshot?)
    func detachOverlay()
    func applyWindowMode(_ request: BenchmarkRequest)
    func restoreWindowMode()
    /// False when the view cannot draw without its frame cap.
    func startUncappedFrames() -> Bool
    func stopUncappedFrames()
}

/// What `BenchmarkWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol BenchmarkWorldHost: AnyObject, SendableMetatype {
    var agentWorld: any AgentWorldPort { get }
    var benchmarkLoadPhases: (any LoadPhaseRecorderPort)? { get }
    var benchmarkTour: any BenchmarkTourPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var sessionStartTiming: SessionStartTiming { get }
    var simulationClock: any SteppedWallClockPort { get }
    var streamer: any CellStreamerPort { get }
    var worldLoadReport: WorldLoadReport? { get }
}

/// A finished run and the folder its files went to.
public struct BenchmarkRun {
    let result: BenchmarkTourResult
    public let folder: URL
    public let writeError: String?
}

public final class BenchmarkWorldAdapter {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Benchmark"
    )
    /// The overlay redraws every this many frames, so drawing it costs the tour little.
    private static let overlayFrames = 6
    /// The frames a tour waits after its last screenshot request, so the capture lands.
    private static let screenshotFrames = 30
    private static let millisecondsPerSecond = 1000.0
    public let game: any BenchmarkWorldHost
    public var tour: any BenchmarkTourPort {
        game.benchmarkTour
    }

    public let state = BenchmarkPartState()
    /// The game window side of a tour, set by the session scope.
    public var view: (any BenchmarkViewPort)? {
        get { state.view }
        set { state.view = newValue }
    }

    /// Started on the first frame the world is ready.
    public var pendingRequest: BenchmarkRequest?
    /// Measures the app start once, for the first tour after launch.
    public var reportsAppStart = false
    private(set) var lastRun: BenchmarkRun?
    /// Counts finished runs, so a waiting caller sees its own run end.
    public private(set) var runCount = 0
    /// Called when a run starts (true) and when it ends (false).
    public var onRunningChange: ((Bool) -> Void)?
    public var onFinish: ((BenchmarkRun) -> Void)?

    public var arrival: (any AgentTeleportJobPort)? {
        get { state.arrival }
        set { state.arrival = newValue }
    }

    private var arrivalStep: AgentWaitStep?
    var request: BenchmarkRequest {
        get { state.request }
        set { state.request = newValue }
    }

    private var ticks = 0
    private var frameSteps = 0
    /// Frames the GPU drew; a frame whose slot the GPU still held is not one.
    public var framesDrawn: Int {
        frameSteps - (game.gameSession?.renderer.skippedFrames ?? 0)
    }

    private var plugins: Set<String> = []
    /// PNGs the tour asked for; the first one waits for its window copy.
    private var screenshots: [URL] = []
    /// A finished run waits for its last PNGs, so a quit right after it keeps them.
    private var finishing: (result: BenchmarkTourResult, framesLeft: Int)?

    public let tourSettingsHost: any BenchmarkTourSettingsHost

    public var tourSettings: BenchmarkTourSettingsAdapter {
        BenchmarkTourSettingsAdapter(game: tourSettingsHost, state: state)
    }

    /// Monotonic seconds for frame timing, and the wall clock for report names.
    public let mediaClock: () -> Double
    public let wallClock: () -> Date

    public init(
        game: some BenchmarkWorldHost & BenchmarkTourSettingsHost,
        mediaClock: @escaping () -> Double,
        wallClock: @escaping () -> Date
    ) {
        self.mediaClock = mediaClock
        self.wallClock = wallClock
        tourSettingsHost = game
        self.game = game
        state.finishAfterScreenshots = { [weak self] in self?.finishAfterScreenshots($0) }
    }

    public var isRunning: Bool {
        tour.isRunning
    }

    /// Starts now when the world is ready, otherwise on the first ready frame.
    public func start(_ request: BenchmarkRequest) throws(BenchmarkRequestError) {
        _ = try request.scenes()
        _ = try request.settingOverrides()
        pendingRequest = request
        frame()
    }

    public func stop() {
        pendingRequest = nil
        tour.stop()
    }

    func frame() {
        frameSteps += 1
        if let request = pendingRequest, game.agentWorld.isWorldReady {
            pendingRequest = nil
            begin(request)
        }
        writeReadyScreenshot()
        drainFinish()
        guard tour.isRunning else { return }
        // A loading screen or a door shows the HUD again when it ends.
        game.gameSession?.renderer.swfEnabled = false
        tour.tick()
        ticks += 1
        if ticks % Self.overlayFrames == 0 {
            view?.showOverlay(tour.snapshot)
        }
    }

    private func begin(_ request: BenchmarkRequest) {
        self.request = request
        plugins =
            Set((game.agentWorld.dataRoot.map { PluginLoadOrder.resolve(root: $0).entries } ?? [])
                    .map { $0.name.lowercased() })
        view?.attachOverlay(enabled: request.overlay)
        let device = game.gameSession?.renderer.device
        let machine = BenchmarkMachine.current(gpu: device?.name ?? "unknown")
        do {
            try tour.start(request, machine: machine, appStart: takeAppStart())
            onRunningChange?(true)
            view?.applyWindowMode(request)
        } catch {
            view?.detachOverlay()
        }
    }

    private func takeAppStart() -> BenchmarkAppStart? {
        guard reportsAppStart, let report = game.worldLoadReport else { return nil }
        reportsAppStart = false
        let sinceStart = BenchmarkAppStart.processStart()
            .map { wallClock().timeIntervalSince($0) * Self.millisecondsPerSecond }
        return BenchmarkAppStart(
            report: report, session: game.sessionStartTiming, processToWorldReadyMS: sinceStart
        )
    }

    public func finishAfterScreenshots(_ result: BenchmarkTourResult) {
        guard !screenshots.isEmpty else {
            finish(result)
            return
        }
        finishing = (result, Self.screenshotFrames)
    }

    private func drainFinish() {
        guard let (result, framesLeft) = finishing else { return }
        guard screenshots.isEmpty || framesLeft == 0 else {
            finishing = (result, framesLeft - 1)
            return
        }
        if !screenshots.isEmpty {
            let count = screenshots.count
            Self.logger.error("[ERROR] benchmark PNGs not written: \(count, privacy: .public)")
            screenshots = []
        }
        finishing = nil
        finish(result)
    }

    private func finish(_ result: BenchmarkTourResult) {
        view?.detachOverlay()
        view?.restoreWindowMode()
        let folder = request.outDirectory.map { URL(filePath: $0) }
            ?? BenchmarkReport.defaultFolder(startedAt: result.startedAt)
        var writeError: String?
        do {
            try BenchmarkReport.write(result, to: folder)
        } catch {
            writeError = String(describing: error)
        }
        let run = BenchmarkRun(result: result, folder: folder, writeError: writeError)
        lastRun = run
        runCount += 1
        onRunningChange?(false)
        onFinish?(run)
    }
}

extension BenchmarkWorldAdapter: BenchmarkTourWorld {
    public var now: Double {
        mediaClock()
    }

    public var date: Date {
        wallClock()
    }

    public var frameSize: (width: Int, height: Int) {
        let size = view?.drawableSize ?? .zero
        return (Int(size.width), Int(size.height))
    }

    public var loadedPlugins: Set<String> {
        plugins
    }

    public func startArrival(at place: BenchmarkPlace) {
        let target: AgentTeleportTarget = switch place {
        case let .exterior(worldspace, x, y):
            {
                let cell = CellCoordinate(containing: SIMD3(x, y, 0))
                return .grid(x: cell.x, y: cell.y, worldspace: worldspace)
            }()
        case let .interior(cell):
            .cell(cell)
        }
        arrivalStep = nil
        do {
            arrival = try game.agentWorld.teleportJob(to: target)
        } catch {
            arrival = nil
            arrivalStep = .done(.failure(error))
        }
    }

    public func arrivalProgress() -> BenchmarkArrival {
        if arrivalStep?.finish == nil, let arrival {
            arrivalStep = arrival.wait.poll(now)
        }
        switch arrivalStep?.finish {
        case nil:
            return .moving
        case let .failure(error)?:
            return .failed(error.message)
        case .success?:
            guard let session = game.gameSession else { return .failed("the world closed") }
            let eye = session.walkController.capsule.eyeHeight
            return .arrived(feet: session.freeFlyCamera.position - SIMD3(0, 0, eye))
        }
    }

    public var isStreamingSettled: Bool {
        let streamer = game.streamer
        return streamer.transitionInFlight == nil && streamer.inFlightCellCount == 0
            && streamer.pendingCompletionCount == 0 && streamer.queuedRequestCount == 0
    }

    public func groundHeight(x: Float, y: Float) -> Float? {
        measurements.groundHeight(x: x, y: y)
    }

    public func isBlocked(_ point: SIMD3<Float>, radius: Float) -> Bool {
        measurements.isBlocked(point, radius: radius)
    }

    public func crossesCollision(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        measurements.crossesCollision(from: start, to: end)
    }

    public func setHour(_ hour: Float) {
        measurements.setHour(hour)
    }

    public func setWeather(_ editorID: String?) -> Bool {
        measurements.setWeather(editorID)
    }

    public func setCamera(_ pose: BenchmarkCameraPose) {
        measurements.setCamera(pose)
    }

    public func stepFixedFrame(seconds: Double) {
        game.simulationClock.requestSteps(1, seconds: seconds)
    }

    public func frameSample() -> BenchmarkFrameSample {
        measurements.frameSample()
    }

    public func takeGPUFrameTimes() -> GPUFrameReport {
        measurements.takeGPUFrameTimes()
    }

    public func takePassTimes() -> [[GPUPass: Double]] {
        measurements.takePassTimes()
    }

    public func gpuMemory() -> GPUMemoryUsage {
        measurements.gpuMemory()
    }

    public func resetArrivalPhases() {
        game.benchmarkLoadPhases?.reset()
    }

    public func arrivalPhases() -> LoadPhaseTimes? {
        measurements.arrivalPhases()
    }

    public func captureFrame(
        to url: URL,
        done: @escaping (Result<URL, FrameCaptureError>) -> Void
    ) {
        measurements.captureFrame(to: url, done: done)
    }

    public func saveScreenshot(to url: URL) {
        screenshots.append(url)
        if screenshots.count == 1 {
            game.gameSession?.renderer.requestWindowCapture()
        }
    }

    /// The copy is readable a frame or two after it was encoded.
    private func writeReadyScreenshot() {
        guard
            let url = screenshots.first,
            let renderer = game.gameSession?.renderer,
            let texture = renderer.takeWindowCapture()
        else { return }
        screenshots.removeFirst()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FrameScreenshot.write(texture: texture, to: url)
        } catch {
            let reason = "\(url.lastPathComponent): \(error)"
            Self.logger.error("[ERROR] benchmark screenshot: \(reason, privacy: .public)")
        }
        if !screenshots.isEmpty {
            renderer.requestWindowCapture()
        }
    }
}

extension BenchmarkWorldAdapter: BenchmarkWorldPort {}

extension BenchmarkWorldAdapter {
    var measurements: BenchmarkMeasurements {
        BenchmarkMeasurements(game: game)
    }
}

struct BenchmarkMeasurements {
    /// A probe pushed farther than this, in units, started inside something.
    private static let pushedOut: Float = 0.01
    let game: any BenchmarkWorldHost

    func groundHeight(x: Float, y: Float) -> Float? {
        game.streamer.sampleTerrain(at: SIMD2(x, y))?.height
    }

    func isBlocked(_ point: SIMD3<Float>, radius: Float) -> Bool {
        guard let query = game.gameSession?.collisionQuery else { return false }
        let capsule = PlayerCapsule.ball(radius: radius)
        let bottom = point - SIMD3(0, 0, radius)
        let probe = CapsuleWorldCollider(capsule: capsule)
            .move(from: bottom, displacement: .zero, query: query)
        return probe.hasUnresolvedPenetration || simd_distance(probe.position, bottom) > Self
            .pushedOut
            || probe.contacts.contains { $0.depth > 0 }
    }

    func crossesCollision(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        let line = end - start
        let streamer = game.streamer
        guard
            let ray = InteractionRay(
                origin: start, direction: line, maximumDistance: simd_length(line)
            )
        else { return false }
        return streamer.nearestCollisionHit(ray: ray) != nil
    }

    func setHour(_ hour: Float) {
        game.runtimeState.setGameClockHour(hour)
    }

    func setWeather(_ editorID: String?) -> Bool {
        guard let weather = game.gameSession?.weather else { return false }
        // A scene without a weather shows its own place's, not the last scene's.
        guard let editorID else {
            weather.resumeAutomatic()
            return true
        }
        let match = weather.store.selectableWeathers().first {
            $0.editorID?.caseInsensitiveCompare(editorID) == .orderedSame
        }
        guard let match else { return false }
        weather.forceWeather(match.formID, transition: .instant)
        return true
    }

    func setCamera(_ pose: BenchmarkCameraPose) {
        game.gameSession?.freeFlyCamera = FreeFlyCamera(
            position: pose.eye,
            yaw: pose.yaw,
            pitch: pose.pitch
        )
    }

    func frameSample() -> BenchmarkFrameSample {
        guard let session = game.gameSession else {
            return BenchmarkFrameSample(cpuMS: [:], drawCalls: 0, drawnInstances: 0)
        }
        let renderer = session.renderer
        let stats = renderer.lastDrawStats
        return BenchmarkFrameSample(
            cpuMS: [
                .simulation: session.lastSimulationMS, .animation: renderer.lastAnimationUpdateMS,
                .shadows: renderer.lastShadowUpdateMS, .encode: renderer.lastEncodeMS,
                .scripts: session.lastScriptUpdateMS, .audio: session.lastAudioUpdateMS
            ],
            drawCalls: stats.drawCalls, drawnInstances: stats.drawnInstances
        )
    }

    func takeGPUFrameTimes() -> GPUFrameReport {
        game.gameSession?.renderer.gpuFrameLog?.take() ?? GPUFrameReport()
    }

    func takePassTimes() -> [[GPUPass: Double]] {
        game.gameSession?.renderer.passTimer?.take() ?? []
    }

    func gpuMemory() -> GPUMemoryUsage {
        var usage = game.gameSession?.renderer.gpuMemoryUsage() ?? GPUMemoryUsage()
        usage.processBytes = MemoryFootprint.physFootprintBytes().map { Int($0) } ?? 0
        if let cached = game.streamer.cachedAssetCounts {
            usage.cachedTextures = cached.textures
            usage.cachedModels = cached.models
        }
        return usage
    }

    func arrivalPhases() -> LoadPhaseTimes? {
        game.benchmarkLoadPhases?.snapshot()
    }

    func captureFrame(
        to url: URL,
        done: @escaping (Result<URL, FrameCaptureError>) -> Void
    ) {
        guard let renderer = game.gameSession?.renderer else {
            done(.failure(.notEnabled))
            return
        }
        renderer.captureNextFrame(to: url, done: done)
    }
}
