// Instruments intervals for the tour and each scene, so a trace lines up with the result.

import OSLog

struct BenchmarkSignposts {
    private static let signposter = OSSignposter(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Benchmark"
    )
    private var tour: OSSignpostIntervalState?
    private var scene: OSSignpostIntervalState?

    mutating func beginTour(_ preset: String) {
        tour = Self.signposter.beginInterval("Tour", "\(preset, privacy: .public)")
    }

    mutating func endTour() {
        endScene()
        if let tour {
            Self.signposter.endInterval("Tour", tour)
        }
        tour = nil
    }

    mutating func beginScene(_ id: String) {
        endScene()
        scene = Self.signposter.beginInterval("Scene", "\(id, privacy: .public)")
    }

    mutating func endScene() {
        if let scene {
            Self.signposter.endInterval("Scene", scene)
        }
        scene = nil
    }

    func mark(_ step: StaticString) {
        Self.signposter.emitEvent(step)
    }
}

/// What the overlay shows about the running tour.
nonisolated public struct BenchmarkTourSnapshot: Equatable, Sendable {
    public enum Step: String, Sendable {
        case loading, arriving, settling, measuring
    }

    public var sceneNumber: Int
    public var sceneCount: Int
    public var title: String
    public var step: Step
    /// Of the current step, from 0 to 1.
    public var progress: Double
    public var fps: Double?
}
