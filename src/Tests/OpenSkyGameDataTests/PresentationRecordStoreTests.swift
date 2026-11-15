// A loading screen's model over synthetic plugins: its STAT is read when asked.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import Testing

struct PresentationRecordStoreTests {
    private static func screen(_ formID: UInt32, model: UInt32) -> Data {
        var link = Data()
        link.appendUInt32(model)
        return ESMFixture.record("LSCR", formID: formID, data: ESMFixture.field("NNAM", link))
    }

    private static func staticObject(_ formID: UInt32, path: String) -> Data {
        ESMFixture.record(
            "STAT", formID: formID, data: ESMFixture.field("MODL", ESMFixture.zstring(path))
        )
    }

    private static func message(_ formID: UInt32) -> Data {
        ESMFixture.record(
            "MESG", formID: formID, data: ESMFixture.field("DESC", ESMFixture.zstring("Hi"))
        )
    }

    @Test func aLoadingScreenReadsTheModelOfItsStatic() throws {
        let file = try ESMFixture.plugin(records: [
            Self.screen(0x10, model: 0x20), Self.screen(0x11, model: 0x30),
            Self.staticObject(0x20, path: "Clutter\\Book.nif"), Self.message(0x30)
        ])
        let store = PresentationRecordStore(plugins: [("Base.esm", file)])
        let screens = Dictionary(
            uniqueKeysWithValues: store.loadScreens.records.map { ($0.record.formID.rawValue, $0) }
        )
        let shown = try #require(screens[0x10])
        let pointsAtAMessage = try #require(screens[0x11])
        #expect(store.model(of: shown) == "Clutter\\Book.nif")
        #expect(store.model(of: pointsAtAMessage) == nil)
    }
}
