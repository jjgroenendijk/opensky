// The audio record stores count a record that fails to decode instead of
// dropping it without a trace.

import Foundation
@testable import OpenSkyAudio
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import Testing

struct AudioRecordStoreSkipTests {
    @Test func acousticSpaceStoreCountsAMalformedSpace() throws {
        let store = try AcousticSpaceStore(file: Self.plugin(types: ["ASPC"]))
        #expect(store.spaces.isEmpty)
        #expect(store.skippedRecords.count(of: "ASPC") == 1)
    }

    @Test func musicRecordStoreCountsMalformedTypesAndTracks() throws {
        let store = try MusicRecordStore(file: Self.plugin(types: ["MUSC", "MUST"]))
        #expect(store.musicTypes.isEmpty)
        #expect(store.musicTracks.isEmpty)
        #expect(store.skippedRecords.count(of: "MUSC") == 1)
        #expect(store.skippedRecords.count(of: "MUST") == 1)
    }

    @Test func footstepStoreCountsEveryMalformedChainRecord() throws {
        let types = ["FSTS", "FSTP", "IPDS", "IPCT"]
        let store = try FootstepStore(file: Self.plugin(types: types))
        #expect(store.sets.isEmpty)
        #expect(store.footsteps.isEmpty)
        #expect(store.skippedRecords.total == types.count)
    }

    /// One malformed record in a top group of each type.
    private static func plugin(types: [String]) throws -> ESMFile {
        var data = ESMFixture.tes4()
        for (offset, type) in types.enumerated() {
            let record = ESMFixture.malformedRecord(type, formID: 0x100 + UInt32(offset))
            data += ESMFixture.topGroup(type, contents: record)
        }
        return try ESMFile(data: data)
    }
}
