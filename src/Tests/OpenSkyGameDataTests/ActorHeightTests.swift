// An actor's height: its own share times its race's height for its sex.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

struct ActorHeightTests {
    /// RACE DATA, 128 bytes, with the male and female heights at 0x10.
    private func race(male: Float, female: Float) throws -> Race {
        var data = Data(count: 0x10)
        data.appendUInt32(male.bitPattern)
        data.appendUInt32(female.bitPattern)
        data.append(Data(count: 128 - data.count))
        return try Race(
            record: ESMFixture.parseRecord(ESMFixture.record(
                "RACE", formID: 0x13746, data: ESMFixture.field("DATA", data)
            )),
            localized: false
        )
    }

    @Test func theHeightIsTheActorsShareTimesTheRacesHeightForItsSex() throws {
        let altmer = try race(male: 1.1, female: 1.05)
        #expect(ActorHeight.scale(npcHeight: 1.0, race: altmer, isFemale: false) == 1.1)
        #expect(abs(ActorHeight.scale(npcHeight: 0.98, race: altmer, isFemale: true) - 1.029) <
            1e-5)
    }

    @Test func aMissingOrZeroValueCountsAsOne() throws {
        #expect(ActorHeight.scale(npcHeight: 1.03, race: nil, isFemale: false) == 1.03)
        #expect(try ActorHeight.scale(npcHeight: 0, race: race(male: 0, female: 1), isFemale: false)
            == 1)
    }
}
