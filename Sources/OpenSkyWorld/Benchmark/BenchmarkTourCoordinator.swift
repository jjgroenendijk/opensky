// Runs the tour: the load passes, then for each scene arrive, warm up, and fly
// the measured shot. `tick` runs once per frame in the `.benchmark` frame step,
// so the world advances one fixed step per frame. See docs/tools/benchmark.md.

import Foundation
import OpenSkyRendering
import simd

@MainActor
public final class BenchmarkTourCoordinator {
    public static let stepSeconds = 1.0 / 60
    /// Two seconds of frames after streaming settles, before a shot is measured.
    static let warmupSteps = 120
    static let arrivalTimeoutSeconds = 150.0
    static let settleTimeoutSeconds = 45.0
    /// GPU memory is sampled every this many measured frames, because a sample walks the residency
    /// set.
    static let memoryInterval = 30

    public enum Phase {
        case idle
        case loading
        case arriving(started: Double)
        case settling(Settling)
        case measuring(origin: SIMD3<Float>, step: Int)
    }

    /// A scene between its arrival and its first measured frame.
    public struct Settling: Equatable {
        public let origin: SIMD3<Float>
        public let started: Double
        public let arrived: Double
        /// Nil until streaming settles, then the warm-up frames run so far.
        public var settledSteps: Int?
    }

    public private(set) var phase = Phase.idle
    public private(set) var lastResult: BenchmarkTourResult?
    /// Called once with the result when the tour ends or is stopped.
    public var onFinish: ((BenchmarkTourResult) -> Void)?

    private weak var world: (any BenchmarkTourWorld)?
    private(set) var request = BenchmarkRequest()
    private var scenes: [BenchmarkScene] = []
    private var index = 0
    private var result: BenchmarkTourResult?
    private var current: BenchmarkSceneResult?
    private var recorder = BenchmarkSceneRecorder()
    private var allFrameMS: [Double] = []
    private var allGPUMS: [Double] = []
    private var memory = GPUMemoryTracker()
    private var lastTick: Double?
    private var recentFrameMS: [Double] = []
    private var tourStarted = 0.0
    private var signposts = BenchmarkSignposts()

    public init(world: any BenchmarkTourWorld) {
        self.world = world
    }

    public var isRunning: Bool {
        if case .idle = phase {
            return false
        }
        return true
    }

    public var snapshot: BenchmarkTourSnapshot? {
        let step: BenchmarkTourSnapshot.Step
        var progress = 0.0
        switch phase {
        case .idle: return nil
        case .loading: step = .loading
        case .arriving: step = .arriving
        case let .settling(settling):
            step = .settling
            progress = Double(settling.settledSteps ?? 0) / Double(Self.warmupSteps)
        case let .measuring(_, measured):
            step = .measuring
            let seconds = index < scenes.count ? scenes[index].shot.seconds : 1
            progress = min(1, Double(measured) * Self.stepSeconds / seconds)
        }
        let average = recentFrameMS.isEmpty ? nil : recentFrameMS
            .reduce(0, +) / Double(recentFrameMS.count)
        return BenchmarkTourSnapshot(
            sceneNumber: min(index + 1, scenes.count), sceneCount: scenes.count,
            title: index < scenes.count ? scenes[index].title : "", step: step,
            progress: progress, fps: average.flatMap { $0 > 0 ? 1000 / $0 : nil }
        )
    }

    /// Checks the request, then starts the tour on the next tick.
    public func start(
        _ request: BenchmarkRequest, machine: BenchmarkMachine, appStart: BenchmarkAppStart? = nil
    ) throws(BenchmarkRequestError) {
        guard let world else { return }
        let scenes = try request.scenes()
        let overrides = try request.settingOverrides()
        self.request = request
        self.scenes = scenes
        index = 0
        allFrameMS = []
        allGPUMS = []
        memory = GPUMemoryTracker()
        lastTick = nil
        tourStarted = world.now
        var result = BenchmarkTourResult(
            startedAt: Date(),
            machine: machine,
            preset: request.preset
        )
        result.appStart = appStart
        result.overrides = request.settings
        result.passTiming = true
        (result.frameWidth, result.frameHeight) = world.frameSize
        world.beginTour(overrides: overrides, passTiming: true)
        result.settings = world.activeSettings
        self.result = result
        signposts.beginTour(request.preset.rawValue)
        if request.loadPasses, let inputs = world.loadInputs, let first = firstPlayableScene() {
            phase = .loading
            Task { [weak self] in
                let passes = try? await BenchmarkLoadPasses.run(place: first.place, inputs: inputs)
                self?.finishLoadPasses(passes)
            }
        } else {
            beginScene()
        }
    }

    /// Ends the tour now; the scenes measured so far stay in the result.
    public func stop() {
        guard isRunning else { return }
        result?.stopped = true
        finishTour()
    }

    public func tick() {
        guard isRunning, let world else { return }
        let now = world.now
        let interval = lastTick.map { ($0 < now ? now - $0 : 0) * 1000 }
        lastTick = now
        if let interval {
            recentFrameMS = Array((recentFrameMS + [interval]).suffix(30))
        }
        world.stepFixedFrame(seconds: Self.stepSeconds)
        switch phase {
        case .idle, .loading:
            break
        case let .arriving(started):
            arrive(world: world, started: started, now: now)
        case let .settling(settling):
            awaitSettling(settling, world: world, now: now)
        case let .measuring(origin, step):
            measure(world: world, origin: origin, step: step, interval: interval)
        }
    }
}

/// The steps sit in an extension, which can still reach the private state of this file.
extension BenchmarkTourCoordinator {
    private func finishLoadPasses(_ passes: (cold: BenchmarkLoadPass, warm: BenchmarkLoadPass)?) {
        guard case .loading = phase else { return }
        result?.coldLoad = passes?.cold
        result?.warmLoad = passes?.warm
        beginScene()
    }

    private func firstPlayableScene() -> BenchmarkScene? {
        scenes.first { isPlayable($0) }
    }

    private func isPlayable(_ scene: BenchmarkScene) -> Bool {
        guard let plugin = scene.requiredPlugin else { return true }
        return world?.loadedPlugins.contains(plugin.lowercased()) ?? false
    }

    private func beginScene() {
        guard let world else { return }
        while index < scenes.count, !isPlayable(scenes[index]) {
            let scene = scenes[index]
            let note = "needs \(scene.requiredPlugin ?? "a plugin"), which the load order lacks"
            result?.scenes.append(BenchmarkSceneResult(scene: scene, status: .skipped, note: note))
            index += 1
        }
        while result?.stopped == true, index < scenes.count {
            result?.scenes.append(
                BenchmarkSceneResult(
                    scene: scenes[index], status: .skipped, note: "the tour was stopped"
                )
            )
            index += 1
        }
        guard index < scenes.count else {
            finishTour()
            return
        }
        let scene = scenes[index]
        current = BenchmarkSceneResult(scene: scene, status: .measured)
        current?.hour = scene.hour
        recorder = BenchmarkSceneRecorder()
        signposts.beginScene(scene.id)
        world.resetArrivalPhases()
        world.startArrival(at: scene.place)
        phase = .arriving(started: world.now)
    }

    private func arrive(world: any BenchmarkTourWorld, started: Double, now: Double) {
        let scene = scenes[index]
        switch world.arrivalProgress() {
        case .moving:
            if now - started > Self.arrivalTimeoutSeconds {
                failScene("did not arrive in \(Int(Self.arrivalTimeoutSeconds)) s")
            }
        case let .failed(message):
            failScene(message)
        case let .arrived(feet):
            let origin = Self.origin(of: scene.place, feet: feet, world: world)
            world.setHour(scene.hour)
            if world.setWeather(scene.weather) {
                current?.weather = scene.weather
            } else if let weather = scene.weather {
                current?.note = "weather \(weather) is not selectable here"
            }
            world.setCamera(scene.shot.pose(at: 0, origin: origin))
            signposts.mark("arrived")
            phase = .settling(Settling(origin: origin, started: started, arrived: now))
        }
    }

    private func awaitSettling(_ settling: Settling, world: any BenchmarkTourWorld, now: Double) {
        let scene = scenes[index]
        world.setCamera(scene.shot.pose(at: 0, origin: settling.origin))
        var settling = settling
        if settling.settledSteps == nil {
            let timedOut = now - settling.arrived > Self.settleTimeoutSeconds
            if world.isStreamingSettled || timedOut {
                current?.arrivalMS = (now - settling.started) * 1000
                current?.arrivalPhases = world.arrivalPhases()
                if timedOut {
                    let limit = Int(Self.settleTimeoutSeconds)
                    current?.note = "streaming did not settle in \(limit) s"
                }
                settling.settledSteps = 0
                signposts.mark("settled")
            }
        }
        guard let settled = settling.settledSteps, settled >= Self.warmupSteps else {
            settling.settledSteps = settling.settledSteps.map { $0 + 1 }
            phase = .settling(settling)
            return
        }
        _ = world.takeGPUFrameTimes()
        _ = world.takePassTimes()
        if request.captureScene == scene.id {
            requestCapture(scene: scene, world: world)
        }
        signposts.mark("measure")
        phase = .measuring(origin: settling.origin, step: 0)
    }

    private func measure(
        world: any BenchmarkTourWorld, origin: SIMD3<Float>, step: Int, interval: Double?
    ) {
        let scene = scenes[index]
        if step > 0, let interval {
            recorder.add(frameMS: interval, sample: world.frameSample())
        }
        recorder.add(gpuMS: world.takeGPUFrameTimes(), passes: world.takePassTimes())
        if step % Self.memoryInterval == 0 {
            let usage = world.gpuMemory()
            recorder.add(memory: usage)
            memory.add(usage)
        }
        let elapsed = Double(step) * Self.stepSeconds
        guard elapsed <= scene.shot.seconds else {
            finishScene()
            return
        }
        world.setCamera(scene.shot.pose(at: elapsed, origin: origin))
        phase = .measuring(origin: origin, step: step + 1)
    }

    private func requestCapture(scene: BenchmarkScene, world: any BenchmarkTourWorld) {
        let folder = request.outDirectory.map { URL(filePath: $0) }
            ?? FileManager.default.temporaryDirectory
        let url = folder.appending(path: "\(scene.id).gputrace")
        let sceneID = scene.id
        world.captureFrame(to: url) { [weak self] outcome in
            self?.recordCapture(outcome, sceneID: sceneID)
        }
    }

    private func recordCapture(_ outcome: Result<URL, FrameCaptureError>, sceneID: String) {
        let apply: (inout BenchmarkSceneResult) -> Void = { scene in
            switch outcome {
            case let .success(url): scene.capturePath = url.path(percentEncoded: false)
            case let .failure(error): scene.note = error.description
            }
        }
        if current?.id == sceneID, var scene = current {
            apply(&scene)
            current = scene
        } else if
            var tour = result,
            let position = tour.scenes.firstIndex(where: { $0.id == sceneID })
        {
            apply(&tour.scenes[position])
            result = tour
        }
    }

    private func failScene(_ message: String) {
        current?.status = .failed
        current?.note = message
        finishScene()
    }

    private func finishScene() {
        if var scene = current {
            recorder.fill(&scene)
            if scene.status == .measured, scene.frameTime == nil {
                let stopped = result?.stopped ?? false
                scene.status = stopped ? .skipped : .failed
                let reason = scene.note ?? "no frames were measured"
                scene.note = stopped ? "the tour was stopped" : reason
            }
            allFrameMS += recorder.frameMS
            allGPUMS += recorder.gpuMS
            result?.scenes.append(scene)
        }
        current = nil
        signposts.endScene()
        index += 1
        beginScene()
    }

    private func finishTour() {
        if current != nil {
            finishScene()
            return
        }
        guard var result else { return }
        world?.endTour()
        result.durationSeconds = (world?.now ?? tourStarted) - tourStarted
        result.frameTime = BenchmarkDistribution(milliseconds: allFrameMS)
        result.gpuTime = BenchmarkDistribution(milliseconds: allGPUMS)
        result.gpuMemory = memory.result
        signposts.endTour()
        phase = .idle
        self.result = nil
        lastResult = result
        onFinish?(result)
    }

    static func origin(
        of place: BenchmarkPlace, feet: SIMD3<Float>, world: any BenchmarkTourWorld
    ) -> SIMD3<Float> {
        switch place {
        case let .exterior(_, x, y):
            SIMD3(x, y, world.groundHeight(x: x, y: y) ?? feet.z)
        case .interior:
            feet
        }
    }
}
