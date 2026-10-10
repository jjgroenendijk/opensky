// Ref ids, vsval widths, and the decoded global data tables, over bytes built in code.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESS
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.parser))
struct ESSGlobalTableTests {
    /// UESP's example: `DragonsAbsorbed` (0x0001C0F2) is stored as 41 C0 F2.
    @Test func refIDReadsBigEndianWithKindBits() throws {
        var reader = ESSReader(Data([0x41, 0xC0, 0xF2]))
        let id = try reader.refID("test")
        #expect(id.kind == .default)
        #expect(id.value == 0x01C0F2)
        #expect(id.formID(in: []) == 0x0001_C0F2)
    }

    @Test func refIDResolvesEachKind() {
        let array: [UInt32] = [0x0100_0D62, 0xFE00_2801]
        #expect(ESSRefID(kind: .formIDArray, value: 2).formID(in: array) == 0xFE00_2801)
        #expect(ESSRefID(kind: .formIDArray, value: 0).formID(in: array) == nil)
        #expect(ESSRefID(kind: .formIDArray, value: 0).isNull)
        #expect(ESSRefID(kind: .formIDArray, value: 3).formID(in: array) == nil)
        #expect(ESSRefID(kind: .created, value: 0x1234).formID(in: array) == 0xFF00_1234)
        #expect(ESSRefID(kind: .unknown, value: 5).formID(in: array) == nil)
    }

    @Test(arguments: [UInt32(0), 0x3F, 0x40, 0x3FFF, 0x4000, 0x3FFFFF])
    func vsvalRoundTripsEachWidth(_ value: UInt32) throws {
        var reader = ESSReader(ESSBytes.build { ESSBytes.vsval(value, into: &$0) })
        #expect(try reader.vsval("test") == value)
        #expect(reader.isAtEnd)
    }

    @Test func decodesMiscStats() throws {
        let data = ESSBytes.build { writer in
            writer.writeUInt32(2)
            ESSBytes.wstring("Locations Discovered", into: &writer)
            writer.writeUInt8(0)
            writer.writeUInt32(14)
            ESSBytes.wstring("Quests Completed", into: &writer)
            writer.writeUInt8(1)
            writer.writeUInt32(3)
        }
        let stats = try ESSMiscStat.decodeAll(data)
        #expect(stats.map(\.name) == ["Locations Discovered", "Quests Completed"])
        #expect(stats.map(\.value) == [14, 3])
        #expect(stats[1].category == 1)
    }

    @Test func decodesPlayerLocation() throws {
        let data = ESSBytes.build { writer in
            writer.writeUInt32(0x42)
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            writer.writeUInt32(UInt32(bitPattern: -3))
            writer.writeUInt32(7)
            ESSBytes.refID(kind: 1, value: 0x3C, into: &writer)
            ESSBytes.vector3(SIMD3(-12000, 30000, 512), into: &writer)
            writer.writeUInt8(0)
        }
        let location = try ESSPlayerLocation.decode(data)
        #expect(location.nextObjectID == 0x42)
        #expect(location.worldspace == ESSRefID(kind: .default, value: 0x3C))
        #expect(location.cell == SIMD2(-3, 7))
        #expect(location.position == SIMD3(-12000, 30000, 512))
    }

    @Test func decodesGlobalVariables() throws {
        let data = ESSBytes.build { writer in
            ESSBytes.vsval(2, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x39, into: &writer)
            writer.writeFloat32(3.5)
            ESSBytes.refID(kind: 0, value: 1, into: &writer)
            writer.writeFloat32(1)
        }
        let globals = try ESSGlobalVariable.decodeAll(data)
        #expect(globals.map(\.value) == [3.5, 1])
        #expect(globals[1].global.kind == .formIDArray)
    }

    @Test func decodesCreatedObjects() throws {
        let data = ESSBytes.build { writer in
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.vsval(0, into: &writer)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 2, value: 0x10, into: &writer)
            writer.writeUInt32(1)
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x3EB15, into: &writer)
            writer.writeFloat32(25)
            writer.writeUInt32(60)
            writer.writeUInt32(0)
            writer.writeFloat32(40)
            ESSBytes.vsval(0, into: &writer)
        }
        let objects = try ESSCreatedObject.decodeAll(data)
        #expect(objects.count == 1)
        #expect(objects[0].kind == .potion)
        #expect(objects[0].form.kind == .created)
        #expect(objects[0].effects.map(\.magnitude) == [25])
        #expect(objects[0].effects.map(\.duration) == [60])
        #expect(objects[0].timesUsed == 1)
        #expect(objects[0].effects.map(\.effect) == [ESSRefID(kind: .default, value: 0x3EB15)])
        #expect(objects[0].effects.map(\.area) == [0])
        #expect(objects[0].effects.map(\.price) == [40])
    }

    @Test func decodesWeatherHead() throws {
        let data = ESSBytes.build { writer in
            for value: UInt32 in [0x0001_2345, 0x0001_2346, 0, 0, 0, 0x0001_2347] {
                ESSBytes.refID(kind: 1, value: value, into: &writer)
            }
            writer.writeFloat32(13.25)
            writer.writeFloat32(12)
            writer.writeFloat32(0.5)
            writer.write(Data(count: 33))
        }
        let weather = try ESSWeather.decode(data)
        #expect(weather.climate == ESSRefID(kind: .default, value: 0x0001_2345))
        #expect(weather.weather == ESSRefID(kind: .default, value: 0x0001_2346))
        #expect(weather.regionWeather == ESSRefID(kind: .default, value: 0x0001_2347))
        #expect(weather.previousWeather.isNull == false)
        #expect(weather.currentHour == 13.25)
        #expect(weather.transition == 0.5)
    }

    @Test func fileFindsTablesByType() throws {
        var fixture = ESSFixture()
        let globals = ESSBytes.build { writer in
            ESSBytes.vsval(1, into: &writer)
            ESSBytes.refID(kind: 1, value: 0x38, into: &writer)
            writer.writeFloat32(9)
        }
        fixture.globalData1 = [(type: 0, data: Data([0, 0, 0, 0])), (type: 3, data: globals)]
        let file = try ESSFile(data: fixture.build())
        #expect(try file.globalVariables().map(\.value) == [9])
        #expect(try file.miscStats().isEmpty)
        #expect(try file.playerLocation() == nil)
        #expect(try file.weather() == nil)
    }
}
