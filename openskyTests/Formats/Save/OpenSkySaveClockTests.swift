// CLOK chunk coverage for the OpenSky native save container (issue #164): the
// game clock round-trips, bytes stay deterministic, an absent chunk means the
// vanilla-start clock, and corrupt payloads throw rather than crash.
// See docs/formats/opensky-save.md.

import Foundation
@testable import opensky
import Testing

struct OpenSkySaveClockTests {
    private func encode(clock: GameClock?) -> Data {
        OpenSkySaveEncoder.encode(
            snapshot: .empty,
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata,
            clock: clock
        )
    }

    /// A well-formed file with one hand-built CLOK chunk appended, for the
    /// malformed-payload cases. The decoder's chunk loop runs to end of file,
    /// so an appended chunk is read like any other.
    private func fileWithClockPayload(_ payload: Data) -> Data {
        var data = encode(clock: nil)
        data.append(Data("CLOK".utf8))
        data.appendUInt32(UInt32(payload.count))
        data.append(payload)
        return data
    }

    @Test func clockSurvivesARoundTrip() throws {
        var clock = GameClock(year: 203, month: 2, day: 28, hour: 4.5)
        clock.advance(wallDelta: 12.345, timescale: 20)
        let decoded = try OpenSkySaveDecoder.decode(encode(clock: clock))
        #expect(decoded.clock == clock, "totalGameSeconds is preserved bit-exactly")
    }

    @Test func encodingIsDeterministic() {
        let clock = GameClock(year: 201, month: 8, day: 17, hour: 9)
        #expect(encode(clock: clock) == encode(clock: clock))
        #expect(encode(clock: clock) != encode(clock: GameClock()))
    }

    @Test func absentChunkMeansVanillaStartClock() throws {
        let decoded = try OpenSkySaveDecoder.decode(encode(clock: nil))
        #expect(decoded.clock == nil, "the loader supplies GameClock() for nil")
    }

    @Test func wrongPayloadSizeIsRejected() {
        #expect(throws: OpenSkySaveError.self) {
            try OpenSkySaveDecoder.decode(fileWithClockPayload(Data([1, 2, 3])))
        }
    }

    @Test func nonFiniteOrNegativeSecondsAreRejected() {
        for bad in [Double.nan, .infinity, -1] {
            var payload = Data()
            payload.appendUInt64(bad.bitPattern)
            #expect(throws: OpenSkySaveError.self) {
                try OpenSkySaveDecoder.decode(fileWithClockPayload(payload))
            }
        }
    }
}
