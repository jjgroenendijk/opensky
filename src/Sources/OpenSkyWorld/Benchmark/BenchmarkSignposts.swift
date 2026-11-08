// Instruments intervals for the tour and each scene, so a trace lines up with the result.

import OpenSkyWorldInterface
public import OSLog

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
