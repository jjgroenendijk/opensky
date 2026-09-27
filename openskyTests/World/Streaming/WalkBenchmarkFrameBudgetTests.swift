// Walk-route timing policy and active-frame filtering over synthetic samples.
// No Metal device or game data is required.

@testable import opensky
import Testing

struct WalkBenchmarkFrameBudgetTests {
    @Test
    func debugDefaultKeepsAverageStrictAndAllowsTwoFrameP95() {
        let budget = WalkBenchmarkFrameBudget.buildDefault(
            frameIntervalMS: 1000.0 / 30,
            debugBuild: true
        )

        #expect(abs(budget.averageMS - 1000.0 / 30) < 1e-9)
        #expect(abs(budget.percentile95MS - 2000.0 / 30) < 1e-9)
        #expect(budget.contains(Self.result(average: 33, percentile95: 60)))
        #expect(!budget.contains(Self.result(average: 34, percentile95: 60)))
        #expect(!budget.contains(Self.result(average: 33, percentile95: 70)))
    }

    @Test
    func releaseDefaultAndExplicitOverrideAreStrict() {
        let release = WalkBenchmarkFrameBudget.buildDefault(
            frameIntervalMS: 40,
            debugBuild: false
        )
        let explicit = WalkBenchmarkFrameBudget.strict(frameIntervalMS: 40)

        #expect(release == explicit)
        #expect(release.contains(Self.result(average: 39, percentile95: 40)))
        #expect(!release.contains(Self.result(average: 39, percentile95: 41)))
    }

    @Test
    func activePhysicsResultFiltersEveryMetricAndDropsFullRunSummaries() {
        let render = OffscreenBenchResult(
            frameMS: [1, 2, 3, 4],
            windowSummaries: ["all four frames"],
            animationMS: [10, 20, 30, 40],
            shadowMS: [100, 200, 300, 400],
            audioUpdateMS: [1000, 2000, 3000, 4000],
            scriptUpdateMS: [10000, 20000, 30000, 40000]
        )

        let active = CellStreamingWalkBenchmark.activePhysicsResult(
            render: render,
            frameMask: [false, true, false, true]
        )

        #expect(active.frameMS == [2, 4])
        #expect(active.animationMS == [20, 40])
        #expect(active.shadowMS == [200, 400])
        #expect(active.audioUpdateMS == [2000, 4000])
        #expect(active.scriptUpdateMS == [20000, 40000])
        #expect(active.windowSummaries.isEmpty)
    }

    private static func result(
        average: Double,
        percentile95: Double
    ) -> OffscreenBenchResult {
        let lowSampleCount = 94
        let highSampleCount = 6
        let sampleCount = lowSampleCount + highSampleCount
        let low = (average * Double(sampleCount) - percentile95 * Double(highSampleCount))
            / Double(lowSampleCount)
        return OffscreenBenchResult(
            frameMS: Array(repeating: low, count: lowSampleCount)
                + Array(repeating: percentile95, count: highSampleCount),
            windowSummaries: []
        )
    }
}
