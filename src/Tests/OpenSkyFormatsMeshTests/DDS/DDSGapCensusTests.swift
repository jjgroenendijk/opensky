// DDSGapCensus: texture variants DDSFile reads, and the ones it does not.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct DDSGapCensusTests {
    @Test func sortsTexturesIntoReadAndUnreadVariants() {
        var census = DDSGapCensus()
        census.record(data: DDSFixture.file(
            width: 4, height: 4, fourCC: "DXT1", payload: Data(count: 8)
        ))
        census.record(data: DDSFixture.file(
            width: 4, height: 4, fourCC: "ZZZZ", payload: Data(count: 8)
        ))
        census.record(data: Data("not a texture".utf8))

        #expect(census.variants.uses["bc1"] == 1)
        #expect(census.variants.done(where: DDSGapCensus.isRead) == 1)
        let left = census.variants.left(where: DDSGapCensus.isRead).map(\.name)
        #expect(left.contains("unsupported: FourCC ZZZZ"))
        #expect(left.contains { $0.hasPrefix("malformed: ") })
    }
}
