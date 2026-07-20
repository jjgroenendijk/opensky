// OffscreenBenchResult math: average + nearest-rank percentile over
// synthetic frame times — the numbers the `bench` fps gate asserts on, so
// the arithmetic itself is pinned here (no Metal, no game data).

@testable import opensky
import Testing

struct OffscreenBenchResultTests {
    @Test
    func averageAndPercentileOverKnownSamples() {
        // 1...100 ms: avg 50.5, nearest-rank p95 = 95th value, p50 = 50th.
        let times = (1 ... 100).map(Double.init)
        let result = OffscreenBenchResult(frameMS: times, windowSummaries: [])
        #expect(abs(result.averageMS - 50.5) < 1e-9)
        #expect(result.percentileMS(95) == 95)
        #expect(result.percentileMS(50) == 50)
        #expect(result.percentileMS(100) == 100)
    }

    @Test
    func percentileIsOrderIndependent() {
        let result = OffscreenBenchResult(
            frameMS: [30, 10, 50, 20, 40],
            windowSummaries: [],
            animationMS: [3, 1, 5, 2, 4]
        )
        #expect(result.percentileMS(95) == 50)
        #expect(abs(result.averageMS - 30) < 1e-9)
        #expect(result.animationPercentileMS(95) == 5)
        #expect(abs(result.animationAverageMS - 3) < 1e-9)
    }

    @Test
    func singleSampleAndEmptyRunEdges() {
        let one = OffscreenBenchResult(frameMS: [16.6], windowSummaries: [])
        #expect(one.percentileMS(95) == 16.6)
        #expect(one.averageMS == 16.6)
        let empty = OffscreenBenchResult(frameMS: [], windowSummaries: [])
        #expect(empty.percentileMS(95) == 0)
        #expect(empty.averageMS == 0)
        #expect(empty.animationPercentileMS(95) == 0)
        #expect(empty.animationAverageMS == 0)
    }
}
