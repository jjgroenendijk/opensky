// `NiStringExtraData` over synthetic files: the `Prn` parent bone of a prop.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct NIFStringExtraDataTests {
    private func extraData(name: UInt32, value: UInt32) -> Data {
        var data = Data()
        data.appendUInt32(name)
        data.appendUInt32(value)
        return data
    }

    @Test func readsTheParentBoneOfAProp() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("BSFadeNode", Data(count: 4)),
                .init("NiStringExtraData", extraData(name: 0, value: 1)),
                .init("NiStringExtraData", extraData(name: 2, value: 3))
            ],
            strings: ["PE", "Weapon", "Prn", "AnimObjectR"]
        ))
        #expect(NIFStringExtraData.all(in: file).map(\.value) == ["Weapon", "AnimObjectR"])
        #expect(NIFStringExtraData.parentBone(in: file) == "AnimObjectR")
    }

    @Test func aMissingOrShortBlockNamesNoBone() throws {
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                .init("NiStringExtraData", extraData(name: .max, value: 9)),
                .init("NiStringExtraData", Data(count: 3))
            ],
            strings: ["Prn"]
        ))
        let all = NIFStringExtraData.all(in: file)
        #expect(all.count == 1)
        #expect(all.first?.name == nil)
        #expect(all.first?.value == nil)
        #expect(NIFStringExtraData.parentBone(in: file) == nil)
    }
}
