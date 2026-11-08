// GapCounts: the done and left split every gap census prints.

import Foundation
@testable import OpenSkyFormatsCore
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct GapCountsTests {
    @Test func splitsItemsByWhetherTheyAreHandled() {
        var counts = GapCounts()
        counts.add("read")
        counts.add("missing", count: 3)
        counts.add("other")
        counts.add("other")

        #expect(counts.total == 6)
        #expect(counts.done { $0 == "read" } == 1)
        let left = counts.left { $0 == "read" }
        #expect(left.map(\.name) == ["missing", "other"])
        #expect(left.map(\.count) == [3, 2])
    }

    @Test func equalCountsRankByName() {
        #expect(GapCounts.ranked(["b": 1, "a": 1, "c": 2]).map(\.name) == ["c", "a", "b"])
    }

    @Test func aFailureKindHidesItsNumbers() {
        #expect(GapCounts.failureKind("block 12 at 0x40 ends early") == "block # at #x# ends early")
    }
}
