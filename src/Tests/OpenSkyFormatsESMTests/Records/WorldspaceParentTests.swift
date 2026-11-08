// WRLD PNAM parent flags: the bits xEdit lists, and which worldspace a
// category comes from when parents chain.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct WorldspaceParentTests {
    private func world(_ formID: UInt32, _ name: String, parent: UInt32?, flags: UInt16) throws
        -> Worldspace
    {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(name))
        if let parent {
            var wnam = Data()
            wnam.appendUInt32(parent)
            var pnam = Data()
            pnam.appendUInt16(flags)
            fields += ESMFixture.field("WNAM", wnam) + ESMFixture.field("PNAM", pnam)
        }
        let bytes = ESMFixture.record("WRLD", formID: formID, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return try Worldspace(record: record, localized: false)
    }

    /// docs/formats/world-records.md, from xEdit's TES5 definitions.
    @Test func parentFlagBitsMatchTheDocumentedList() {
        let documented: [(Worldspace.ParentFlags, UInt16)] = [
            (.useLandData, 0x01), (.useLODData, 0x02), (.useMapData, 0x04),
            (.useWaterData, 0x08), (.useClimateData, 0x10), (.useSkyCell, 0x40)
        ]
        for (flag, bits) in documented {
            #expect(flag.rawValue == bits)
        }
    }

    @Test func aCategoryComesFromTheParentOnlyWhenItsFlagIsSet() throws {
        let tamriel = try world(0x3C, "Tamriel", parent: nil, flags: 0)
        let city = try world(0x40, "WhiterunWorld", parent: 0x3C, flags: 0x7F)
        let markarth = try world(0x41, "MarkarthWorld", parent: 0x3C, flags: 0x44)
        let worlds: [UInt32: Worldspace] = [0x3C: tamriel, 0x40: city, 0x41: markarth]
        #expect(city.source(of: .useLODData, in: worlds).editorID == "Tamriel")
        #expect(city.source(of: .useClimateData, in: worlds).editorID == "Tamriel")
        #expect(markarth.source(of: .useMapData, in: worlds).editorID == "Tamriel")
        #expect(markarth.source(of: .useLODData, in: worlds).editorID == "MarkarthWorld")
    }

    @Test func aParentCycleStops() throws {
        let first = try world(0x50, "First", parent: 0x51, flags: 0x01)
        let second = try world(0x51, "Second", parent: 0x50, flags: 0x01)
        let worlds: [UInt32: Worldspace] = [0x50: first, 0x51: second]
        #expect(first.source(of: .useLandData, in: worlds).editorID == "Second")
    }
}
