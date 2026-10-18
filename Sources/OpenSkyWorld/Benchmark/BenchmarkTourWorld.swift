// The port the tour drives. The app adapts its running game to it; a test
// passes a fake. Every call runs on the main actor, inside the frame.

import Foundation
import OpenSkyGameData
import OpenSkyRendering
import simd

/// A per-frame CPU cost the tour reports, each read from the frame before.
nonisolated public enum BenchmarkCPUProbe: String, CaseIterable, Codable, Sendable {
    /// Camera, frame steps, game clock, world tick, and weather.
    case simulation
    case animation
    case shadows
    /// The shadow and scene pass encode.
    case encode
    case scripts
    case audio
}

nonisolated public struct BenchmarkFrameSample: Equatable, Sendable {
    public var cpuMS: [BenchmarkCPUProbe: Double]
    public var drawCalls: Int
    public var drawnInstances: Int

    public init(cpuMS: [BenchmarkCPUProbe: Double], drawCalls: Int, drawnInstances: Int) {
        self.cpuMS = cpuMS
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
    }
}

nonisolated public enum BenchmarkArrival: Equatable, Sendable {
    case moving
    /// Where the player stands once the destination cells are in.
    case arrived(feet: SIMD3<Float>)
    case failed(String)
}

@MainActor
public protocol BenchmarkTourWorld: AnyObject {
    /// Seconds of a monotonic real clock, for frame intervals.
    var now: Double { get }
    var frameSize: (width: Int, height: Int) { get }
    /// Lowercased plugin names of the load order.
    var loadedPlugins: Set<String> { get }
    /// Every setting that differs from its default, as the tour runs with it.
    var activeSettings: [String: Double] { get }

    /// Freezes the clock, takes the camera, hides the HUD, and applies `overrides`.
    func beginTour(overrides: [PlayerSettingID: Double], passTiming: Bool)
    /// Gives everything `beginTour` took back.
    func endTour()

    func startArrival(at place: BenchmarkPlace)
    func arrivalProgress() -> BenchmarkArrival
    /// No cell build is queued or running.
    var isStreamingSettled: Bool { get }
    func groundHeight(x: Float, y: Float) -> Float?
    /// A sphere of `radius` at `point` overlaps static collision, such as a rock or a wall.
    func isBlocked(_ point: SIMD3<Float>, radius: Float) -> Bool
    /// The straight line from `start` to `end` hits static collision.
    func crossesCollision(from start: SIMD3<Float>, to end: SIMD3<Float>) -> Bool

    func setHour(_ hour: Float)
    /// False when the weather cannot be selected here.
    func setWeather(_ editorID: String?) -> Bool
    func setCamera(_ pose: BenchmarkCameraPose)
    /// Lets the clock advance one fixed step on the next frame.
    func stepFixedFrame(seconds: Double)

    func frameSample() -> BenchmarkFrameSample
    /// GPU spans and pass times that arrived since the last call.
    func takeGPUFrameTimes() -> [Double]
    func takePassTimes() -> [[GPUPass: Double]]
    func gpuMemory() -> GPUMemoryUsage
    /// Starts counting asset phases of the streamer's builds; nil when no recorder is attached.
    func resetArrivalPhases()
    func arrivalPhases() -> LoadPhaseTimes?

    func captureFrame(to url: URL, done: @escaping (Result<URL, FrameCaptureError>) -> Void)
    /// Writes the next frame the window presents as a PNG at `url`.
    func saveScreenshot(to url: URL)
    /// The inputs for a cold builder, or nil when the session has no game data.
    var loadInputs: BenchmarkLoadInputs? { get }
}
