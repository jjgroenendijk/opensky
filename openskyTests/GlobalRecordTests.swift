// GLOB decoder coverage over synthetic field bytes only. Layout source: UESP
// "Skyrim Mod:Mod File Format/GLOB" and xEdit `wbRecord(GLOB, ...)`; see
// docs/formats/records.md.

import Foundation
@testable import opensky
import Testing

struct GlobalRecordTests {
    @Test func decodesFloatGlobal() throws {
        let global = try Global(record: GlobalFixture.parse(GlobalFixture.record(
            formID: 0x0100_0800, editorID: "TimeScale", type: .float, value: 20.5
        )))
        #expect(global.formID == FormID(0x0100_0800))
        #expect(global.editorID == "TimeScale")
        #expect(global.valueType == .float)
        #expect(global.defaultValue.value == 20.5)
        #expect(global.defaultValue.integerValue == nil)
        #expect(!global.isConstant)
    }

    @Test func decodesShortAndLongGlobals() throws {
        let short = try Global(record: GlobalFixture.parse(GlobalFixture.record(
            formID: 0x10, editorID: "ShortOne", type: .short, value: 7
        )))
        #expect(short.valueType == .short)
        #expect(short.defaultValue.value == 7)
        #expect(short.defaultValue.integerValue == 7)

        let long = try Global(record: GlobalFixture.parse(GlobalFixture.record(
            formID: 0x11, editorID: "LongOne", type: .long, value: 1_234_567
        )))
        #expect(long.valueType == .long)
        #expect(long.defaultValue.integerValue == 1_234_567)
    }

    /// FLTV is a float32 whatever FNAM declares, so an integer-typed global can
    /// carry a fraction on disk. It is rounded on decode, not preserved.
    @Test func roundsFractionalValueOntoIntegerType() throws {
        let short = try Global(record: GlobalFixture.parse(GlobalFixture.record(
            formID: 0x12, editorID: "Rounded", type: .short, value: 3.7
        )))
        #expect(short.defaultValue.value == 4)
        let negative = try Global(record: GlobalFixture.parse(GlobalFixture.record(
            formID: 0x13, editorID: "Negative", type: .long, value: -2.5
        )))
        // Half away from zero, the documented rule.
        #expect(negative.defaultValue.value == -3)
    }

    @Test func readsConstantHeaderFlag() throws {
        let global = try Global(record: GlobalFixture.parse(GlobalFixture.record(
            formID: 0x14, editorID: "Fixed", type: .float, value: 1, isConstant: true
        )))
        #expect(global.isConstant)
    }

    @Test func rejectsWrongRecordType() throws {
        let bytes = ESMFixture.record("GRAS", data: Data())
        #expect(throws: ESMError.self) {
            try Global(record: GlobalFixture.parse(bytes))
        }
    }

    /// A type character outside the documented s/l/f set leaves the xEdit
    /// default (Float) in place rather than losing the record.
    @Test func unknownTypeCharacterFallsBackToFloat() throws {
        var fltv = Data()
        fltv.appendUInt32(Float(2.25).bitPattern)
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Odd"))
            + ESMFixture.field("FNAM", Data([UInt8(ascii: "q")]))
            + ESMFixture.field("FLTV", fltv)
        let global = try Global(record: GlobalFixture.parse(
            ESMFixture.record("GLOB", formID: 0x20, data: fields)
        ))
        #expect(global.valueType == .float)
        #expect(global.defaultValue.value == 2.25)
    }

    @Test func skipsWrongSizeFields() throws {
        let fields = ESMFixture.field("EDID", ESMFixture.zstring("Broken"))
            + ESMFixture.field("FNAM", Data([UInt8(ascii: "s"), 0]))
            + ESMFixture.field("FLTV", Data([1, 2, 3]))
        let global = try Global(record: GlobalFixture.parse(
            ESMFixture.record("GLOB", formID: 0x21, data: fields)
        ))
        // Two-byte FNAM and three-byte FLTV are both skipped: float, zero.
        #expect(global.editorID == "Broken")
        #expect(global.valueType == .float)
        #expect(global.defaultValue.value == 0)
    }

    @Test func decodesRecordWithNoFields() throws {
        let global = try Global(record: GlobalFixture.parse(
            ESMFixture.record("GLOB", formID: 0x22, data: Data())
        ))
        #expect(global.editorID == nil)
        #expect(global.defaultValue == GlobalValue(type: .float, rawValue: 0))
    }

    @Test func coercesNonFiniteIntegerValueToZero() {
        #expect(GlobalValue(type: .short, rawValue: .nan).value == 0)
        #expect(GlobalValue(type: .long, rawValue: .infinity).value == 0)
        // Float globals keep whatever the plugin authored.
        #expect(GlobalValue(type: .float, rawValue: .infinity).value == .infinity)
    }
}
