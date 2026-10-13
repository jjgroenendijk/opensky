// SWFTagCensus: tags a movie holds, nested sprites included, and which ones a decoder
// reads, over synthetic movies.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsSWF
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct SWFTagCensusTests {
    @Test func countsNestedTagsAndNamesGFxTags() {
        var sprite = Data()
        sprite.appendUInt16(7) // sprite id
        sprite.appendUInt16(1) // frame count
        sprite.append(SWFFixture.tagBytes(code: 1, body: Data()))
        sprite.append(SWFFixture.tagBytes(code: 0, body: Data()))
        var movie = SWFFixture()
        movie.tags = [
            .init(code: 39, body: sprite),
            .init(code: 1009, body: Data(count: 4)),
            .init(code: 1, body: Data())
        ]
        var census = SWFTagCensus()
        census.record(data: movie.build())

        #expect(census.movieCount == 1)
        #expect(census.tags.uses["1 ShowFrame"] == 2)
        #expect(census.tags.uses["1009 DefineExternalImage2"] == 1)
        #expect(census.tags.left(where: SWFTagCensus.isHandled).map(\.name)
            == ["1009 DefineExternalImage2"])
    }

    @Test func aMovieThatDoesNotOpenIsOneFailure() {
        var census = SWFTagCensus()
        census.record(data: Data("XYZ".utf8))
        #expect(census.failures.total == 1)
    }
}
