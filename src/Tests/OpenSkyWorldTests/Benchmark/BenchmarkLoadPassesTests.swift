// A load pass reports the time since its stopwatch started.

import OpenSkyFormatsCore
@testable import OpenSkyWorld
import Testing

struct BenchmarkLoadPassesTests {
    @Test func aPassTimeIsNeverNegative() {
        #expect(BenchmarkLoadPasses.milliseconds(since: Stopwatch()) >= 0)
    }
}
