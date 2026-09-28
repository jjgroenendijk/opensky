// Record builder shared by the parser tests and the runtime tests that feed
// the same records to a store. Every byte is built in code.

import Foundation
@testable import OpenSkyFormats

public enum PackageFixture: Sendable {
    public static func record(formID: UInt32 = 1, fields: Data) throws -> ESMRecord {
        try parse(ESMFixture.record("PACK", formID: formID, data: fields))
    }

    public static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    public static func general(flags: UInt32 = 0, kind: UInt8 = 18, speed: UInt8 = 0) -> Data {
        var data = Data()
        data.appendUInt32(flags)
        data.append(contentsOf: [kind, 0, speed, 0])
        data.appendUInt16(0)
        data.appendUInt16(0)
        return ESMFixture.field("PKDT", data)
    }

    public static func schedule(
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

    public static func scheduleValue(
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

    public static func counter(template: UInt32 = 0) -> Data {
        var data = Data()
        data.appendUInt32(0)
        data.appendUInt32(template)
        data.appendUInt32(1)
        return ESMFixture.field("PKCU", data)
    }

    public static func location(kind: Int32, value: UInt32, radius: Int32) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: kind))
        data.appendUInt32(value)
        data.appendUInt32(UInt32(bitPattern: radius))
        return data
    }

    public static func target(kind: Int32, value: UInt32, tail: Int32) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(bitPattern: kind))
        data.appendUInt32(value)
        data.appendUInt32(UInt32(bitPattern: tail))
        return data
    }
}
