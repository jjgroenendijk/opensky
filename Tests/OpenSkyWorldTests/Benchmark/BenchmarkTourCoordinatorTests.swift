// The tour's steps against a fake world: arrive, settle, warm up, measure, and
// skip a scene whose plugin is missing. No Metal device or game data.

import Foundation
import OpenSkyGameData
import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
private final class FakeTourWorld: BenchmarkTourWorld {
    var now = 0.0
    var frameSize = (width: 1280, height: 720)
    var loadedPlugins: Set = ["skyrim.esm"]
    var activeSettings: [String: Double] = ["rendering.renderScale": 2]
    var isStreamingSettled = true
    var loadInputs: BenchmarkLoadInputs?
    var arrival = BenchmarkArrival.arrived(feet: SIMD3(0, 0, 50))
    var began: [PlayerSettingID: Double]?
    var endCount = 0
    var arrivals: [BenchmarkPlace] = []
    var cameras: [BenchmarkCameraPose] = []
    var hours: [Float] = []
    var steps = 0
    var captures: [URL] = []

    func beginTour(overrides: [PlayerSettingID: Double], passTiming _: Bool) {
        began = overrides
    }

    func endTour() {
        endCount += 1
    }

    func startArrival(at place: BenchmarkPlace) {
        arrivals.append(place)
    }

    func arrivalProgress() -> BenchmarkArrival {
        arrival
    }

    func groundHeight(x _: Float, y _: Float) -> Float? {
        100
    }

    func setHour(_ hour: Float) {
        hours.append(hour)
    }

    func setWeather(_ editorID: String?) -> Bool {
        editorID != nil
    }

    func setCamera(_ pose: BenchmarkCameraPose) {
        cameras.append(pose)
    }

    func stepFixedFrame(seconds: Double) {
        steps += 1
        now += seconds
    }

    func frameSample() -> BenchmarkFrameSample {
        BenchmarkFrameSample(
            cpuMS: [.encode: 2, .simulation: 1],
            drawCalls: 300,
            drawnInstances: 900
        )
    }

    func takeGPUFrameTimes() -> [Double] {
        [8]
    }

    func takePassTimes() -> [[GPUPass: Double]] {
        [[.scene: 3, .shadows: 2]]
    }

    func gpuMemory() -> GPUMemoryUsage {
        GPUMemoryUsage(totalBytes: 1 << 30, renderTargetBytes: 1 << 26, textureBytes: 1 << 28)
    }

    func resetArrivalPhases() {}

    func arrivalPhases() -> LoadPhaseTimes? {
        nil
    }

    func captureFrame(to url: URL, done: @escaping (Result<URL, FrameCaptureError>) -> Void) {
        captures.append(url)
        done(.success(url))
    }
}

@MainActor
struct BenchmarkTourCoordinatorTests {
    private static let machine = BenchmarkMachine(
        modelIdentifier: "Mac0,0", cpu: "CPU", gpu: "GPU", logicalCores: 8, memoryGB: 16,
        osVersion: "26"
    )

    private func runToEnd(_ tour: BenchmarkTourCoordinator, limit: Int = 20000) {
        var ticks = 0
        while tour.isRunning, ticks < limit {
            tour.tick()
            ticks += 1
        }
    }

    @Test func aTourMeasuresEachSceneAndSkipsAMissingPlugin() throws {
        let world = FakeTourWorld()
        let tour = BenchmarkTourCoordinator(world: world)
        var finished: BenchmarkTourResult?
        tour.onFinish = { finished = $0 }
        let request = BenchmarkRequest(
            sceneIDs: ["whiterun", "forgottenVale"], settings: ["rendering.gpuCulling": 0],
            loadPasses: false
        )
        try tour.start(request, machine: Self.machine)
        runToEnd(tour)

        let result = try #require(finished)
        #expect(world.began?[.gpuCulling] == 0)
        #expect(world.endCount == 1)
        #expect(result.scenes.map(\.status) == [.measured, .skipped])
        #expect(result.scenes[1].note?.contains("Dawnguard.esm") == true)
        let whiterun = result.scenes[0]
        let shot = try #require(BenchmarkTour.scene(id: "whiterun")).shot
        let frames = try #require(whiterun.frameTime).frames
        #expect(abs(frames - Int(shot.seconds * 60)) <= 2)
        #expect(whiterun.cpu["encode"]?.averageMS == 2)
        #expect(whiterun.passes["scene"]?.averageMS == 3)
        #expect(whiterun.averageDrawCalls == 300)
        #expect(whiterun.gpuMemory != nil)
        #expect(whiterun.arrivalMS != nil)
        #expect(result.settings == ["rendering.renderScale": 2])
        #expect(result.overrides == ["rendering.gpuCulling": 0])
        #expect(result.isComparable)
        #expect(tour.lastResult == result)
        // The exterior origin stands on the sampled ground, not on the arrival feet.
        let origin = SIMD3<Float>(19855, -7422, 100)
        #expect(world.cameras.contains(shot.pose(at: 0, origin: origin)))
        #expect(world.arrivals.count == 1)
    }

    @Test func aSceneThatNeverArrivesFails() throws {
        let world = FakeTourWorld()
        world.arrival = .failed("no such cell")
        let tour = BenchmarkTourCoordinator(world: world)
        try tour.start(
            BenchmarkRequest(sceneIDs: ["dragonsreach"], loadPasses: false),
            machine: Self.machine
        )
        runToEnd(tour)
        let scene = try #require(tour.lastResult?.scenes.first)
        #expect(scene.status == .failed)
        #expect(scene.note == "no such cell")
        #expect(tour.lastResult?.isComparable == false)
    }

    @Test func settlingWaitsForStreamingBeforeTheWarmUp() throws {
        let world = FakeTourWorld()
        world.isStreamingSettled = false
        let tour = BenchmarkTourCoordinator(world: world)
        try tour.start(
            BenchmarkRequest(sceneIDs: ["whiterun"], loadPasses: false),
            machine: Self.machine
        )
        for _ in 0 ..< 200 {
            tour.tick()
        }
        #expect(tour.snapshot?.step == .settling)
        #expect(tour.snapshot?.progress == 0)
        world.isStreamingSettled = true
        for _ in 0 ..< BenchmarkTourCoordinator.warmupSteps + 2 {
            tour.tick()
        }
        #expect(tour.snapshot?.step == .measuring)
    }

    @Test func stopKeepsTheMeasuredScenesAndMarksTheRest() throws {
        let world = FakeTourWorld()
        world.arrival = .moving
        let tour = BenchmarkTourCoordinator(world: world)
        try tour.start(
            BenchmarkRequest(sceneIDs: ["whiterun", "riften"], loadPasses: false),
            machine: Self.machine
        )
        tour.tick()
        tour.stop()
        let result = try #require(tour.lastResult)
        #expect(result.stopped)
        #expect(result.scenes.map(\.status) == [.skipped, .skipped])
        #expect(world.arrivals.count == 1)
        #expect(!tour.isRunning)
        #expect(world.endCount == 1)
    }

    @Test func theCaptureSceneWritesOneTrace() throws {
        let world = FakeTourWorld()
        let tour = BenchmarkTourCoordinator(world: world)
        let request = BenchmarkRequest(
            sceneIDs: ["dragonsreach"], outDirectory: "/tmp/bench", captureScene: "dragonsreach",
            loadPasses: false
        )
        try tour.start(request, machine: Self.machine)
        runToEnd(tour)
        #expect(world.captures.map(\.lastPathComponent) == ["dragonsreach.gputrace"])
        #expect(tour.lastResult?.scenes.first?.capturePath == "/tmp/bench/dragonsreach.gputrace")
    }

    @Test func aBadRequestStartsNothing() {
        let world = FakeTourWorld()
        let tour = BenchmarkTourCoordinator(world: world)
        #expect(throws: BenchmarkRequestError.unknownScene("nowhere")) {
            try tour.start(
                BenchmarkRequest(sceneIDs: ["nowhere"]),
                machine: Self.machine
            )
        }
        #expect(!tour.isRunning)
        #expect(world.began == nil)
    }
}
