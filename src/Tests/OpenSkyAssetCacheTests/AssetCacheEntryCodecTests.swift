// The entry layout: a header round trip, the payload alignment, and bad files.

import Foundation
@testable import OpenSkyAssetCache
import Testing

struct AssetCacheEntryCodecTests {
    private let header = AssetCacheEntryHeader(
        kind: .mesh,
        source: AssetSourceStamp(
            origin: "loose",
            path: "meshes\\a.nif",
            size: 12,
            modified: -5,
            contentHash: 99
        ),
        converterVersion: 3,
        output: 0x42
    )

    @Test func theHeaderAndPayloadRoundTrip() throws {
        let file = AssetCacheEntryCodec.encode(header: header, payload: Data([4, 5, 6]))
        let (decoded, range) = try AssetCacheEntryCodec.decode(file)
        #expect(decoded == header)
        #expect(Data(file[range]) == Data([4, 5, 6]))
        #expect(range.lowerBound % AssetCacheEntryCodec.payloadAlignment == 0)
    }

    @Test func aFileWithAnotherMagicIsRejected() {
        var file = AssetCacheEntryCodec.encode(header: header, payload: Data([1]))
        file[0] = 0x58
        #expect(throws: AssetCacheEntryError.badMagic) { try AssetCacheEntryCodec.decode(file) }
    }

    @Test func aShortOrLongFileIsTruncated() {
        let file = AssetCacheEntryCodec.encode(
            header: header,
            payload: Data(repeating: 1, count: 32)
        )
        #expect(throws: AssetCacheEntryError.truncated) {
            try AssetCacheEntryCodec.decode(file.prefix(40))
        }
        #expect(throws: AssetCacheEntryError.truncated) {
            try AssetCacheEntryCodec.decode(file + Data([0]))
        }
    }
}
