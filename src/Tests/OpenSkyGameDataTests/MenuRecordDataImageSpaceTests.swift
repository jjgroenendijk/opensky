// The `LSIS` default object names the image space the main menu and loading screen
// scenes draw through. Synthetic DOBJ and IMGS records.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct MenuRecordDataImageSpaceTests {
    private static func records(lsis object: UInt32, type: String) throws -> MenuRecordData {
        var dobj = Data("LSIS".utf8)
        dobj.appendUInt32(object)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("LoadScreenIS"))
            + ESMFixture.field("CNAM", ESMFixture.f32(0.75, 0.9, 1))
        let data = ESMFixture.tes4()
            + ESMFixture.topGroup("DOBJ", contents: ESMFixture.record(
                "DOBJ", formID: 0x31, data: ESMFixture.field("DNAM", dobj)
            ))
            + ESMFixture.topGroup(type, contents: ESMFixture.record(
                type, formID: 0x40, data: fields
            ))
        return try MenuRecordData(
            loadOrder: LoadOrderPlugins([("Base.esm", ESMFile(data: data))]),
            settings: GameSettingStore(plugins: [])
        )
    }

    @Test func theLoadScreenDefaultObjectNamesItsImageSpace() throws {
        let records = try Self.records(lsis: 0x40, type: "IMGS")
        let cinematic = records.loadScreenImageSpace?.cinematic
        #expect(cinematic?.saturation == 0.75)
        #expect(cinematic?.brightness == 0.9)
    }

    @Test func aDefaultObjectThatIsNoImageSpaceGivesNone() throws {
        #expect(try Self.records(lsis: 0x40, type: "STAT").loadScreenImageSpace == nil)
        #expect(try Self.records(lsis: 0x99, type: "IMGS").loadScreenImageSpace == nil)
    }
}
