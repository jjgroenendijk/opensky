// PLOC chunk: the player's place survives a round trip, an absent chunk means no
// place, and a payload without a cell or with a value that is not finite throws.
// See docs/formats/opensky-save-world-chunks.md.

@testable import FormatsTesting
import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyWorldState
import Testing

struct OpenSkySavePlayerPlaceTests {
    private func encode(place: SavePlayerPlace?) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: .empty,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            playerPlace: place
        )
    }

    private func fileWithPlacePayload(_ payload: Data) -> Data {
        var data = encode(place: nil)
        data.append(Data("PLOC".utf8))
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    @Test func exteriorAndInteriorPlacesSurviveARoundTrip() throws {
        let places = [
            SavePlayerPlace(
                cell: .exterior(CellCoordinate(x: 5, y: -24)),
                feet: SIMD3(22468.2, -96140.9, 14293.3),
                yaw: -2.35
            ),
            SavePlayerPlace(cell: .interior(FormID(0x1605E)), feet: SIMD3(10, -20, 64), yaw: 0.5)
        ]
        for place in places {
            #expect(try OpenSkySaveDecoder.decode(encode(place: place)).playerPlace == place)
        }
    }

    @Test func absentChunkMeansNoPlace() throws {
        #expect(try OpenSkySaveDecoder.decode(encode(place: nil)).playerPlace == nil)
    }

    @Test func aPlaceWithoutACellOrWithANaNIsRejected() {
        var noCell = Data([0])
        for _ in 0 ..< 4 {
            noCell.appendUInt32(Float(1).bitPattern)
        }
        var notFinite = Data([1])
        notFinite.appendUInt32(0)
        notFinite.appendUInt32(0)
        for value in [Float(1), .nan, 1, 0] {
            notFinite.appendUInt32(value.bitPattern)
        }
        for payload in [noCell, notFinite] {
            #expect(throws: OpenSkySaveError.self) {
                try OpenSkySaveDecoder.decode(fileWithPlacePayload(payload))
            }
        }
    }
}
