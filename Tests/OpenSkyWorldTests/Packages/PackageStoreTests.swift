// PackageStore built from a synthetic plugin: malformed PACK records are counted, and
// template inputs are found by name.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyWorld
import Testing

struct PackageStoreTests {
    @Test func countsMalformedPackageRecord() throws {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                "PACK",
                contents: ESMFixture.malformedRecord("PACK", formID: 0x100)
            )
        let store = try PackageStore(file: ESMFile(data: plugin))

        #expect(store.packages.isEmpty)
        #expect(store.skippedRecords.count(of: "PACK") == 1)
        #expect(store.skippedRecords.byType["PACK"]?.firstError.contains("XXXX") == true)
    }

    @Test func readsRideHorseByTheTemplateInputName() throws {
        let plugin = ESMFixture.tes4()
            + ESMFixture.topGroup(
                "PACK",
                contents: ESMFixture.record("PACK", formID: 0x200, data: Self.travelTemplate)
                    + ESMFixture.record("PACK", formID: 0x300, data: Self.travel(rides: true))
                    + ESMFixture.record("PACK", formID: 0x301, data: Self.travel(rides: nil))
            )
        let store = try PackageStore(file: ESMFile(data: plugin))

        #expect(try store.resolve(FormID(0x300)).ridesHorse)
        #expect(try store.resolve(FormID(0x301)).ridesHorse == false)
        #expect(try store.resolve(FormID(0x300)).procedure == .travel)
    }

    /// The vanilla Travel template's inputs: "Place to Travel" at 0, and
    /// "Ride Horse if possible?" at 2.
    private static var travelTemplate: Data {
        var fields = PackageFixture.general() + PackageFixture.schedule()
        fields += PackageFixture.counter() + Self.inputs(rides: false)
        fields += ESMFixture.field("XNAM", Data())
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("Procedure"))
        fields += ESMFixture.field("PNAM", ESMFixture.zstring("Travel"))
        fields += ESMFixture.field("UNAM", Data([0]))
        fields += ESMFixture.field("BNAM", ESMFixture.zstring("Place to Travel"))
        fields += ESMFixture.field("UNAM", Data([2]))
        fields += ESMFixture.field("BNAM", ESMFixture.zstring("Ride Horse if possible?"))
        return fields
    }

    private static func travel(rides: Bool?) -> Data {
        var fields = PackageFixture.general() + PackageFixture.schedule()
        fields += PackageFixture.counter(template: 0x200)
        fields += rides.map { Self.inputs(rides: $0) } ?? Data()
        return fields
    }

    private static func inputs(rides: Bool) -> Data {
        ESMFixture.field("ANAM", ESMFixture.zstring("Location"))
            + ESMFixture.field("PLDT", PackageFixture.location(kind: 3, value: 0, radius: 0))
            + ESMFixture.field("ANAM", ESMFixture.zstring("Bool"))
            + ESMFixture.field("CNAM", Data([rides ? 1 : 0]))
            + ESMFixture.field("UNAM", Data([0]))
            + ESMFixture.field("UNAM", Data([2]))
    }
}
