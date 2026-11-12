import Foundation

// An agent's tour request is checked as it is parsed: a known preset waits for the world,
// and an unknown preset or scene fails before anything starts.

import OpenSkyAgentAdapters
import OpenSkyAgentControl
import OpenSkyGameData
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct BenchmarkAgentRequestTests {
    private let host = AgentHost()

    private func benchmark() -> BenchmarkWorldAdapter {
        BenchmarkWorldAdapter(game: host, stage: nil, mediaClock: { 0 }, wallClock: { Date() })
    }

    @Test func aKnownPresetWaitsForTheWorld() throws {
        let tours = benchmark()
        var request = AgentBenchmarkRequest()
        request.preset = "Quick"
        request.fullScreen = true
        try tours.start(request)
        #expect(tours.pendingRequest?.preset == .quick)
        #expect(tours.pendingRequest?.display == .fullScreen)
        #expect(tours.lastRunJSON == nil)
    }

    @Test func anUnknownPresetOrSceneFails() {
        let tours = benchmark()
        var preset = AgentBenchmarkRequest()
        preset.preset = "slow"
        #expect(throws: AgentFailure.self) { try tours.start(preset) }
        var scene = AgentBenchmarkRequest()
        scene.scenes = ["NoSuchScene"]
        #expect(throws: AgentFailure.self) { try tours.start(scene) }
        #expect(tours.pendingRequest == nil)
    }
}
