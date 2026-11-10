import Foundation

// The benchmark reads frame time and report dates from the clocks it is given.

import OpenSkyAgentAdapters
import OpenSkyGameData
import OpenSkySessionTesting
import Testing

@MainActor
struct BenchmarkClockTests {
    private let host = AgentHost()

    @Test func theBenchmarkReadsItsClocks() {
        let benchmark = BenchmarkWorldAdapter(
            game: host, stage: nil,
            mediaClock: { 3 }, wallClock: { Date(timeIntervalSinceReferenceDate: 9) }
        )
        #expect(benchmark.now == 3)
        #expect(benchmark.date == Date(timeIntervalSinceReferenceDate: 9))
        #expect(!benchmark.isRunning)
    }

    @Test func arrivalPhasesComeFromTheLoadRecorder() {
        let phases = FakeLoadPhaseRecorderPort()
        phases.snapshotResult = LoadPhaseTimes(archiveMS: 4)
        host.benchmarkLoadPhases = phases
        let benchmark = BenchmarkWorldAdapter(
            game: host, stage: nil, mediaClock: { 0 }, wallClock: { Date() }
        )
        benchmark.resetArrivalPhases()
        #expect(phases.resetCallCount == 1)
        #expect(benchmark.arrivalPhases()?.archiveMS == 4)
    }
}
