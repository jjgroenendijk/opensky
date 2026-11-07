// A seeded stream repeats its draws, and each draw stays inside its range.

@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct RandomStreamTests {
    @Test func oneSeedRepeatsItsDraws() {
        let first = RandomStream(seed: 7)
        let second = RandomStream(seed: 7)
        for _ in 0 ..< 8 {
            #expect(first.float(in: 0 ..< 1) == second.float(in: 0 ..< 1))
            #expect(first.float(in: 2 ... 3) == second.float(in: 2 ... 3))
            #expect(first.int(below: 10) == second.int(below: 10))
        }
    }

    @Test func drawsStayInsideTheirRange() {
        let stream = RandomStream(seed: 11)
        for _ in 0 ..< 64 {
            #expect((0 ..< 1).contains(stream.float(in: 0 ..< 1)))
            #expect((2 ... 3).contains(stream.float(in: 2 ... 3)))
            #expect((0 ..< 5).contains(stream.int(below: 5)))
        }
        #expect(stream.int(below: 0) == 0)
    }
}
