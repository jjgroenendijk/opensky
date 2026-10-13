// RecordCoverageSweep: what the decoder registry cannot decode, over synthetic
// records.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct RecordCoverageSweepTests {
    @Test func countsMissingDecodersAndUnreadFields() throws {
        var sweep = RecordCoverageSweep()
        try sweep.decode(ESMFixture.record("HAZD", fields: []), localized: false)
        try sweep.decode(ESMFixture.record("ZZZZ", fields: []), localized: false)
        try sweep.decode(
            ESMFixture.record("HAZD", fields: [("QQQQ", Data([1]))]), localized: false
        )

        #expect(sweep.recordTotal == 3)
        #expect(sweep.counts["HAZD"] == 2)
        #expect(sweep.missing == ["ZZZZ": 1])
        #expect(sweep.failures.isEmpty)
        #expect(sweep.untallied.isEmpty)
        #expect(sweep.unknownFieldTotal == 1)
        #expect(sweep.unread["HAZD"]?["unknown QQQQ"] == 1)
    }
}
