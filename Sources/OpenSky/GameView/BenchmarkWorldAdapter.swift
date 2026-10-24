// App side of `BenchmarkTourCoordinator`: the live game window as the tour's
// world. It takes the clock, the camera, and the HUD for the run and gives them
// back at the end. The tour rules live in the coordinator (docs/tools/benchmark.md).

import AppKit
import Metal
import MetalKit
import OpenSkyAgentControl
import OpenSkyEffects
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyRuntimeState
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import QuartzCore
import simd

/// What `BenchmarkWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol BenchmarkWorldHost: AnyObject {
    var agentWorld: AgentWorldAdapter { get }
    var benchmarkLoadPhases: LoadPhaseRecorder? { get }
    var effects: EffectsCoordinator { get }
    var gameSession: GameSession? { get }
    var hostView: NSView { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var sessionStartTiming: SessionStartTiming { get }
    var simulationClock: SteppedWallClock { get }
    var streamer: CellStreamer? { get }
    var terrainLODConfigurationStore: TerrainLODConfigurationStore { get }
    var worldLoadReport: WorldLoadReport? { get }
}

/// A finished run and the folder its files went to.
struct BenchmarkRun {
    let result: BenchmarkTourResult
    let folder: URL
    let writeError: String?
}

final class BenchmarkWorldAdapter {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Benchmark"
    )
    unowned let game: any BenchmarkWorldHost
    private(set) lazy var tour = BenchmarkTourCoordinator(world: self)
    let overlay = BenchmarkOverlayView()
    /// Started on the first frame the world is ready.
    var pendingRequest: BenchmarkRequest?
    /// Measures the app start once, for the first tour after launch.
    var reportsAppStart = false
    private(set) var lastRun: BenchmarkRun?
    /// Counts finished runs, so a waiting caller sees its own run end.
    private(set) var runCount = 0
    /// Called when a run starts (true) and when it ends (false).
    var onRunningChange: ((Bool) -> Void)?
    var onFinish: ((BenchmarkRun) -> Void)?

    private var arrival: AgentTeleportJob?
    private var arrivalStep: AgentWaitStep?
    private var saved: SavedState?
    private var request = BenchmarkRequest()
    private var ticks = 0
    private var tourOverrides: [PlayerSettingID: Double] = [:]
    private var plugins: Set<String> = []
    /// PNGs the tour asked for; the first one waits for its window copy.
    private var screenshots: [URL] = []
    /// A finished run waits for its last PNGs, so a quit right after it keeps them.
    private var finishing: (result: BenchmarkTourResult, framesLeft: Int)?
    /// The run put the window in full screen, so its end takes it back out.
    private var enteredFullScreen = false

    private struct SavedState {
        let movementMode: CameraMovementMode
        let wasFrozen: Bool
        let hudEnabled: Bool
        let camera: FreeFlyCamera
        let forcedWeather: FormID?
    }

    init(game: any BenchmarkWorldHost) {
        self.game = game
        tour.onFinish = { [weak self] result in self?.finishAfterScreenshots(result) }
    }

    func wire(gameSession: GameSession) {
        gameSession.frameSteps.register(.benchmark) { [weak self] _ in
            self?.frame()
        }
    }

    var isRunning: Bool {
        tour.isRunning
    }

    /// Starts now when the world is ready, otherwise on the first ready frame.
    func start(_ request: BenchmarkRequest) throws(BenchmarkRequestError) {
        _ = try request.scenes()
        _ = try request.settingOverrides()
        pendingRequest = request
        frame()
    }

    func stop() {
        pendingRequest = nil
        tour.stop()
    }

    private func frame() {
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
        if ticks % 6 == 0 {
            overlay.show(tour.snapshot)
        }
    }

    private func begin(_ request: BenchmarkRequest) {
        self.request = request
        plugins =
            Set((game.agentWorld.dataRoot.map { PluginLoadOrder.resolve(root: $0).entries } ?? [])
                    .map { $0.name.lowercased() })
        overlay.isOverlayEnabled = request.overlay
        overlay.attach(to: game.hostView)
        let device = game.gameSession?.renderer.device
        let machine = BenchmarkMachine.current(gpu: device?.name ?? "unknown")
        do {
            try tour.start(request, machine: machine, appStart: takeAppStart())
            onRunningChange?(true)
            setFullScreen(request.fullScreen)
        } catch {
            overlay.detach()
        }
    }

    private func takeAppStart() -> BenchmarkAppStart? {
        guard reportsAppStart, let report = game.worldLoadReport else { return nil }
        reportsAppStart = false
        let sinceStart = BenchmarkAppStart.processStart()
            .map { Date().timeIntervalSince($0) * 1000 }
        return BenchmarkAppStart(
            report: report, session: game.sessionStartTiming, processToWorldReadyMS: sinceStart
        )
    }

    private func finishAfterScreenshots(_ result: BenchmarkTourResult) {
        guard !screenshots.isEmpty else {
            finish(result)
            return
        }
        finishing = (result, 30)
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

    private func setFullScreen(_ on: Bool) {
        guard let window = game.hostView.window else { return }
        let isFull = window.styleMask.contains(.fullScreen)
        if on, !isFull {
            enteredFullScreen = true
            window.toggleFullScreen(nil)
        } else if !on, enteredFullScreen, isFull {
            window.toggleFullScreen(nil)
        }
        if !on {
            enteredFullScreen = false
        }
    }

    private func finish(_ result: BenchmarkTourResult) {
        overlay.detach()
        setFullScreen(false)
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
    var now: Double {
        CACurrentMediaTime()
    }

    var frameSize: (width: Int, height: Int) {
        let size = (game.hostView as? MTKView)?.drawableSize ?? .zero
        return (Int(size.width), Int(size.height))
    }

    var loadedPlugins: Set<String> {
        plugins
    }

    var activeSettings: [String: Double] {
        let store = game.playerSettingsStore
        var values: [String: Double] = [:]
        for definition in store.catalog.definitions
            where store.value(definition.id) != definition.defaultValue
        {
            values[definition.id.rawValue] = store.value(definition.id)
        }
        for (id, value) in tourOverrides {
            values[id.rawValue] = value
        }
        return values
    }

    func beginTour(overrides: [PlayerSettingID: Double], passTiming: Bool) {
        guard let session = game.gameSession else { return }
        let renderer = session.renderer
        saved = SavedState(
            movementMode: session.movementMode, wasFrozen: game.simulationClock.isFrozen,
            hudEnabled: renderer.swfEnabled, camera: session.freeFlyCamera,
            forcedWeather: session.weather?.forced
        )
        tourOverrides = overrides
        if !overrides.isEmpty {
            apply(PlayerSettingsStore(copying: game.playerSettingsStore, overrides: overrides))
        }
        session.setMovementMode(.fly)
        renderer.swfEnabled = false
        renderer.gpuFrameLog = GPUFrameLog()
        renderer.setPassTimingEnabled(passTiming)
        game.simulationClock.freeze()
    }

    func endTour() {
        guard let session = game.gameSession, let saved else { return }
        let renderer = session.renderer
        renderer.setPassTimingEnabled(false)
        renderer.gpuFrameLog = nil
        renderer.swfEnabled = saved.hudEnabled
        if !tourOverrides.isEmpty {
            apply(game.playerSettingsStore)
        }
        tourOverrides = [:]
        session.weather?.forceWeather(saved.forcedWeather, transition: .instant)
        session.freeFlyCamera = saved.camera
        session.setMovementMode(saved.movementMode)
        if !saved.wasFrozen {
            game.simulationClock.resume()
        }
        arrival = nil
        self.saved = nil
    }

    private func apply(_ store: PlayerSettingsStore) {
        game.gameSession?.applyGraphicsSettings(store)
        game.effects.applyGraphicsSettings(store)
    }

    func startArrival(at place: BenchmarkPlace) {
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
            arrival = try AgentTeleportJob(adapter: game.agentWorld, target: target)
        } catch {
            arrival = nil
            arrivalStep = .done(.failure(error))
        }
    }

    func arrivalProgress() -> BenchmarkArrival {
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

    var isStreamingSettled: Bool {
        guard let streamer = game.streamer else { return true }
        return streamer.transitionInFlight == nil && streamer.inFlightCellCount == 0
            && streamer.pendingCompletionCount == 0 && streamer.queuedRequestCount == 0
    }

    func groundHeight(x: Float, y: Float) -> Float? {
        game.streamer?.sampleTerrain(at: SIMD2(x, y))?.height
    }

    func isBlocked(_ point: SIMD3<Float>, radius: Float) -> Bool {
        guard let query = game.gameSession?.collisionQuery else { return false }
        let capsule = PlayerCapsule(radius: radius, height: radius * 2, eyeHeight: radius)
        let bottom = point - SIMD3(0, 0, radius)
        let probe = CapsuleWorldCollider(capsule: capsule)
            .move(from: bottom, displacement: .zero, query: query)
        return probe.hasUnresolvedPenetration || simd_distance(probe.position, bottom) > 0.01
            || probe.contacts.contains { $0.depth > 0 }
    }

    func crossesCollision(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool {
        let line = end - start
        guard
            let streamer = game.streamer,
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
        guard let editorID, let weather = game.gameSession?.weather else { return false }
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

    func stepFixedFrame(seconds: Double) {
        game.simulationClock.requestSteps(1, seconds: seconds)
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

    func takeGPUFrameTimes() -> [Double] {
        game.gameSession?.renderer.gpuFrameLog?.take() ?? []
    }

    func takePassTimes() -> [[GPUPass: Double]] {
        game.gameSession?.renderer.passTimer?.take() ?? []
    }

    func gpuMemory() -> GPUMemoryUsage {
        game.gameSession?.renderer.gpuMemoryUsage() ?? GPUMemoryUsage()
    }

    func resetArrivalPhases() {
        game.benchmarkLoadPhases?.reset()
    }

    func arrivalPhases() -> LoadPhaseTimes? {
        game.benchmarkLoadPhases?.snapshot()
    }

    func captureFrame(to url: URL, done: @escaping (Result<URL, FrameCaptureError>) -> Void) {
        guard let renderer = game.gameSession?.renderer else {
            done(.failure(.notEnabled))
            return
        }
        renderer.captureNextFrame(to: url, done: done)
    }

    func saveScreenshot(to url: URL) {
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

    var loadInputs: BenchmarkLoadInputs? {
        guard
            let root = game.agentWorld.dataRoot,
            let device = game.gameSession?.renderer.device
        else {
            return nil
        }
        return BenchmarkLoadInputs(
            root: root,
            device: device,
            terrainLOD: game.terrainLODConfigurationStore
        )
    }
}
