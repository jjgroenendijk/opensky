// A stopwatch reads the time since it started, in a duration and in milliseconds.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct StopwatchTests {
    @Test func readingsNeverGoBackwards() {
        let watch = Stopwatch()
        let first = watch.milliseconds
        #expect(first >= 0)
        #expect(watch.milliseconds >= first)
        #expect(watch.elapsed >= .zero)
    }
}
