// CTDA/CITC/CIS1/CIS2 decoder coverage over synthetic field bytes only.
// Layout: UESP "Skyrim Mod:Mod File Format/CTDA Field" and xEdit dev
// Core/wbDefinitionsTES5.pas `wbCTDA` (line 6889).

import Foundation
@testable import opensky
import Testing

struct ConditionTests {
    // MARK: - Whole-payload decode

    @Test func decodesFloatComparison() throws {
        let field = ctda(
            operatorByte: 0x40, // operator 2 (greater than) in the top 3 bits
            comparisonValue: floatBits(12.5),
            functionIndex: 576,
            parameter1: 0x0001_0203,
            parameter2: 0x1122_3344,
            runOn: 1,
            reference: 0xDEAD_BEEF,
            parameter3: -1
        )
        let condition = try #require(try Condition(ctda: field))

        #expect(condition.comparison == .greaterThan)
        #expect(condition.flags.isEmpty)
        #expect(condition.comparisonValue == .value(12.5))
        #expect(condition.functionIndex == 576)
        #expect(condition.parameter1.rawValue == 0x0001_0203)
        #expect(condition.parameter2.rawValue == 0x1122_3344)
        #expect(condition.runOn == .target)
        // The reference word is ignored unless run-on is Reference, and real
        // plugins leave garbage there — it is kept verbatim, never validated.
        #expect(condition.reference == FormID(0xDEAD_BEEF))
        #expect(condition.parameter3 == -1)
        #expect(condition.parameter1Name == nil)
        #expect(condition.parameter2Name == nil)
    }

    @Test func decodesUseGlobalComparisonValue() throws {
        // Flag 0x04 retypes the comparison word from a float to a GLOB FormID.
        let field = ctda(operatorByte: 0x04, comparisonValue: 0x0002_1B4C)
        let condition = try #require(try Condition(ctda: field))

        #expect(condition.flags.contains(.useGlobal))
        #expect(condition.comparison == .equal)
        #expect(condition.comparisonValue == .global(FormID(0x0002_1B4C)))
    }

    @Test func decodesEveryComparisonOperator() throws {
        let expected: [Condition.ComparisonOperator] = [
            .equal, .notEqual, .greaterThan, .greaterThanOrEqual,
            .lessThan, .lessThanOrEqual, .unknown(6), .unknown(7)
        ]
        for (raw, wanted) in expected.enumerated() {
            let field = ctda(operatorByte: UInt8(raw) << 5)
            let condition = try #require(try Condition(ctda: field))
            #expect(condition.comparison == wanted)
            #expect(condition.flags.isEmpty)
        }
    }

    @Test func decodesEveryFlagBit() throws {
        let cases: [(UInt8, Condition.Flags)] = [
            (0x01, .or),
            (0x02, .useAliases),
            (0x04, .useGlobal),
            (0x08, .usePackData),
            (0x10, .swapSubjectAndTarget)
        ]
        for (raw, wanted) in cases {
            // Operator bits set at the same time must not bleed into the flags.
            let field = ctda(operatorByte: (5 << 5) | raw)
            let condition = try #require(try Condition(ctda: field))
            #expect(condition.comparison == .lessThanOrEqual)
            #expect(condition.flags == wanted)
        }
    }

    @Test func decodesEveryRunOnType() throws {
        let expected: [Condition.RunOnType] = [
            .subject, .target, .reference, .combatTarget,
            .linkedReference, .questAlias, .packageData, .eventData
        ]
        for (raw, wanted) in expected.enumerated() {
            let field = ctda(runOn: UInt32(raw))
            let condition = try #require(try Condition(ctda: field))
            #expect(condition.runOn == wanted)
        }
        let odd = try #require(try Condition(ctda: ctda(runOn: 99)))
        #expect(odd.runOn == .unknown(99))
    }

    @Test func ignoresUnusedAndPaddingBytes() throws {
        // Offsets 1-3 and 10-11 hold garbage in real plugins; a decode must not
        // depend on them or reject the field.
        var data = Data([0x00, 0xFF, 0xFF, 0xFF])
        data.appendUInt32(floatBits(1))
        data.appendUInt16(400)
        data.appendUInt16(0xFFFF) // padding
        data.appendUInt32(0)
        data.appendUInt32(0)
        data.appendUInt32(0)
        data.appendUInt32(0)
        data.appendUInt32(UInt32(bitPattern: -1))
        let condition = try #require(try Condition(ctda: ESMField(type: "CTDA", data: data)))
        #expect(condition.functionIndex == 400)
        #expect(condition.comparisonValue == .value(1))
        #expect(condition.runOn == .subject)
    }

    @Test func exposesTypedParameterViews() throws {
        let field = ctda(parameter1: floatBits(-2.75), parameter2: 0xFFFF_FFFF)
        let condition = try #require(try Condition(ctda: field))
        #expect(condition.parameter1.asFloat == -2.75)
        #expect(condition.parameter2.asFormID == FormID(0xFFFF_FFFF))
        #expect(condition.parameter2.asInt32 == -1)
    }

    // MARK: - Malformed input

    @Test func skipsWrongSizeConditionPayload() throws {
        for size in [0, 20, 31, 33, 64] {
            let field = ESMField(type: "CTDA", data: Data(count: size))
            #expect(try Condition(ctda: field) == nil, "size \(size) should be skipped")
        }
    }

    @Test func wrongFieldTypeThrows() throws {
        #expect(throws: ESMError.self) {
            _ = try Condition(ctda: ESMField(type: "CITC", data: Data(count: 32)))
        }
    }

    // MARK: - Condition runs

    @Test func decodesOrFlaggedRun() throws {
        var list = ConditionList()
        try list.decode(field: citc(3))
        try list.decode(field: ctda(operatorByte: 0x01, comparisonValue: floatBits(1)))
        try list.decode(field: ctda(operatorByte: 0x01, comparisonValue: floatBits(2)))
        try list.decode(field: ctda(operatorByte: 0x00, comparisonValue: floatBits(3)))

        #expect(list.declaredCount == 3)
        #expect(list.conditions.count == 3)
        #expect(list.conditions.map { $0.flags.contains(.or) } == [true, true, false])
        #expect(list.conditions.map(\.comparisonValue) == [.value(1), .value(2), .value(3)])
    }

    @Test func attachesParameterNamesToPrecedingCondition() throws {
        var list = ConditionList()
        try list.decode(field: ctda(parameter1: 1))
        try list.decode(field: cis1("MyQuestAlias"))
        try list.decode(field: ctda(parameter1: 2))
        try list.decode(field: cis2("SecondParam"))

        #expect(list.conditions.count == 2)
        #expect(list.conditions[0].parameter1Name == "MyQuestAlias")
        #expect(list.conditions[0].parameter2Name == nil)
        #expect(list.conditions[1].parameter1Name == nil)
        #expect(list.conditions[1].parameter2Name == "SecondParam")
    }

    @Test func dropsParameterNamesWithNoPrecedingCondition() throws {
        var list = ConditionList()
        try list.decode(field: cis1("Orphan"))
        // The CTDA that would have owned it was malformed and skipped.
        try list.decode(field: ESMField(type: "CTDA", data: Data(count: 8)))
        try list.decode(field: cis2("AlsoOrphan"))
        #expect(list.isEmpty)
    }

    @Test func skipsMalformedConditionsInsideRun() throws {
        var list = ConditionList()
        try list.decode(field: citc(2))
        try list.decode(field: ESMField(type: "CTDA", data: Data(count: 30)))
        try list.decode(field: ctda(functionIndex: 45))

        // CITC keeps the authored count; only the decodable CTDA survives.
        #expect(list.declaredCount == 2)
        #expect(list.conditions.count == 1)
        #expect(list.conditions[0].functionIndex == 45)
    }

    @Test func ignoresWrongWidthConditionCount() throws {
        var list = ConditionList()
        #expect(try list.decode(field: ESMField(type: "CITC", data: Data(count: 2))))
        #expect(list.declaredCount == nil)
    }

    @Test func leavesUnrelatedFieldsToTheCaller() throws {
        var list = ConditionList()
        #expect(try !list.decode(field: ESMField(type: "EDID", data: Data())))
        #expect(list.isEmpty)
        #expect(list.declaredCount == nil)
    }

    // MARK: - Fixtures

    private func floatBits(_ value: Float) -> UInt32 {
        value.bitPattern
    }

    /// A well-formed 32-byte CTDA field with per-offset overrides.
    private func ctda(
        operatorByte: UInt8 = 0,
        comparisonValue: UInt32 = 0,
        functionIndex: UInt16 = 0,
        parameter1: UInt32 = 0,
        parameter2: UInt32 = 0,
        runOn: UInt32 = 0,
        reference: UInt32 = 0,
        parameter3: Int32 = -1
    ) -> ESMField {
        var data = Data([operatorByte, 0, 0, 0])
        data.appendUInt32(comparisonValue)
        data.appendUInt16(functionIndex)
        data.appendUInt16(0) // padding
        data.appendUInt32(parameter1)
        data.appendUInt32(parameter2)
        data.appendUInt32(runOn)
        data.appendUInt32(reference)
        data.appendUInt32(UInt32(bitPattern: parameter3))
        return ESMField(type: "CTDA", data: data)
    }

    private func citc(_ count: UInt32) -> ESMField {
        var data = Data()
        data.appendUInt32(count)
        return ESMField(type: "CITC", data: data)
    }

    private func cis1(_ name: String) -> ESMField {
        ESMField(type: "CIS1", data: ESMFixture.zstring(name))
    }

    private func cis2(_ name: String) -> ESMField {
        ESMField(type: "CIS2", data: ESMFixture.zstring(name))
    }
}
