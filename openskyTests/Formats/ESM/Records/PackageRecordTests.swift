// PACK decoder tests use synthetic field bytes only. No game records or
// extracted assets are fixtures (AGENTS.md legal boundary).

import Foundation
@testable import opensky
import Testing

struct PackageRecordTests {
    @Test func decodesBoundedHeaderPublicDataAndProcedureNames() throws {
        let condition = ConditionEvaluatorFixture.field(
            comparisonValue: Float(1).bitPattern,
            functionIndex: 35,
            runOn: 2,
            reference: 0x700
        ).data
        var fields = PackageFixture.general(flags: 0x2404, kind: 18, speed: 2)
        fields += PackageFixture.schedule(hour: 20, minute: 10, duration: 240)
        fields += ESMFixture.field("CTDA", condition)
        fields += PackageFixture.counter(template: 0x200)
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("Location"))
        let locationBytes = PackageFixture.location(kind: 0, value: 0x300, radius: 512)
        fields += ESMFixture.field("PLDT", locationBytes)
        fields += ESMFixture.field("ANAM", ESMFixture.zstring("SingleRef"))
        fields += ESMFixture.field(
            "PTDA", PackageFixture.target(kind: 6, value: 0, tail: 1)
        )
        fields += ESMFixture.field("UNAM", Data([3]))
        fields += ESMFixture.field("UNAM", Data([7]))
        fields += ESMFixture.field("XNAM", Data())
        fields += ESMFixture.field("PNAM", ESMFixture.zstring("Travel"))
        fields += ESMFixture.field("POBA", Data())

        let package = try Package(record: PackageFixture.record(formID: 0x100, fields: fields))
        #expect(package.formID == FormID(0x100))
        #expect(package.general.flags.contains(.mustComplete))
        #expect(package.general.kind == .package)
        #expect(package.general.preferredSpeed == .run)
        #expect(package.schedule.hour == 20)
        #expect(package.schedule.minute == 10)
        #expect(package.schedule.durationMinutes == 240)
        #expect(package.conditions.conditions.map(\.functionIndex) == [35])
        #expect(package.template == FormID(0x200))
        #expect(package.dataInputs.map(\.index) == [3, 7])
        #expect(package.procedureTypes == ["Travel"])

        guard case let .location(location) = package.dataInputs[0].value else {
            Issue.record("first public input was not a location")
            return
        }
        #expect(location.kind == .nearReference)
        #expect(location.formID == FormID(0x300))
        #expect(location.radius == 512)
        guard case let .target(target) = package.dataInputs[1].value else {
            Issue.record("second public input was not a target")
            return
        }
        #expect(target.kind == .actor)
        #expect(target.countOrDistance == 1)
    }

    @Test func preservesUnknownGeneralAndPublicKinds() throws {
        let fields = PackageFixture.general(kind: 250, speed: 249)
            + PackageFixture.schedule()
            + PackageFixture.counter()
            + ESMFixture.field("ANAM", ESMFixture.zstring("Location"))
            + ESMFixture.field("PLDT", PackageFixture.location(kind: 99, value: 7, radius: 8))
            + ESMFixture.field("XNAM", Data())
        let package = try Package(record: PackageFixture.record(fields: fields))
        #expect(package.general.kind == .unknown(250))
        #expect(package.general.preferredSpeed == .unknown(249))
        guard case let .location(location) = package.dataInputs[0].value else {
            Issue.record("unknown location did not survive as location data")
            return
        }
        #expect(location.kind == nil)
        #expect(location.rawKind == 99)
    }

    @Test func rejectsWrongRecordAndMalformedFixedWidthFields() throws {
        let wrong = ESMFixture.record("NPC_", data: Data())
        #expect(throws: ESMError.self) {
            _ = try Package(record: PackageFixture.parse(wrong))
        }
        for (type, bytes) in [("PKDT", 11), ("PSDT", 11), ("PKCU", 11)] {
            let fields = ESMFixture.field(type, Data(count: bytes))
            #expect(throws: ESMError.self) {
                _ = try Package(record: PackageFixture.record(fields: fields))
            }
        }
        for (type, bytes) in [("PLDT", 8), ("PTDA", 8)] {
            let valueType = type == "PLDT" ? "Location" : "SingleRef"
            let fields = PackageFixture.general() + PackageFixture.schedule()
                + PackageFixture.counter()
                + ESMFixture.field("ANAM", ESMFixture.zstring(valueType))
                + ESMFixture.field(type, Data(count: bytes))
            #expect(throws: ESMError.self) {
                _ = try Package(record: PackageFixture.record(fields: fields))
            }
        }
    }

    @Test func scheduleMatchesEdgesWrapsAndCalendarGroups() {
        let evening = PackageFixture.scheduleValue(hour: 20, minute: 10, duration: 240)
        #expect(!evening.matches(GameClock(hour: 20)))
        #expect(evening.matches(GameClock(hour: 20.1667)))
        #expect(evening.matches(GameClock(hour: 0)))
        #expect(!evening.matches(GameClock(hour: 0.1667)))
        #expect(evening.minutesUntilBoundary(after: GameClock(hour: 20)) == 10)

        let sundas = PackageFixture.scheduleValue(weekday: 0)
        let morndas = PackageFixture.scheduleValue(weekday: 1)
        #expect(sundas.matches(GameClock(hour: 12)))
        #expect(!morndas.matches(GameClock(hour: 12)))
        var nextDay = GameClock(hour: 12)
        nextDay.advance(wallDelta: 4320, timescale: 20)
        #expect(morndas.matches(nextDay))

        let sundasOvernight = PackageFixture.scheduleValue(
            weekday: 0, hour: 20, duration: 480
        )
        #expect(sundasOvernight.matches(GameClock(hour: 23)))
        var morndasMorning = GameClock(hour: 1)
        morndasMorning.advance(wallDelta: 4320, timescale: 20)
        #expect(sundasOvernight.matches(morndasMorning))
        #expect(!sundasOvernight.matches(GameClock(hour: 1)))
    }
}

enum PackageFixture {
    static func record(formID: UInt32 = 1, fields: Data) throws -> ESMRecord {
        try parse(ESMFixture.record("PACK", formID: formID, data: fields))
    }

    static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    static func general(flags: UInt32 = 0, kind: UInt8 = 18, speed: UInt8 = 0) -> Data {
        var data = Data()
        data.appendUInt32(flags)
        data.append(contentsOf: [kind, 0, speed, 0])
        data.appendUInt16(0)
        data.appendUInt16(0)
        return ESMFixture.field("PKDT", data)
    }

    static func schedule(
        month: Int8 = -1,
        weekday: Int8 = -1,
        date: Int8 = 0,
        hour: Int8 = -1,
        minute: Int8 = -1,
        duration: UInt32 = 0
    ) -> Data {
        var data = Data([
            UInt8(bitPattern: month), UInt8(bitPattern: weekday), UInt8(bitPattern: date),
            UInt8(bitPattern: hour), UInt8(bitPattern: minute), 0, 0, 0
        ])
        data.appendUInt32(duration)
        return ESMFixture.field("PSDT", data)
    }

    static func scheduleValue(
        weekday: Int8 = -1,
        hour: Int8 = -1,
        minute: Int8 = -1,
        duration: UInt32 = 0
    ) -> Package.Schedule {
        Package.Schedule(
            month: -1,
            dayOfWeek: weekday,
            date: 0,
            hour: hour,
            minute: minute,
            durationMinutes: duration
        )
    }

    static func counter(template: UInt32 = 0) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendUInt32(template)
        data.appendUInt32(1)
        return ESMFixture.field("PKCU", data)
    }

    static func location(kind: Int32, value: UInt32, radius: Int32) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: kind))
        data.appendUInt32(value)
        data.appendUInt32(UInt32(bitPattern: radius))
        return data
    }

    static func target(kind: Int32, value: UInt32, tail: Int32) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: kind))
        data.appendUInt32(value)
        data.appendUInt32(UInt32(bitPattern: tail))
        return data
    }
}
