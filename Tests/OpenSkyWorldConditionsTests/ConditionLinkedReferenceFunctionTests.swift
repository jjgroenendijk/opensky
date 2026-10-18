// HasLinkedRef, IsLinkedTo, and HasRefType over a REFR built in code. Links and
// ref types are FormIDs of the reference's plugin, resolved to keys first.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
import OpenSkyWorldConditions
@testable import OpenSkyWorldState
import Testing

struct ConditionLinkedReferenceFunctionTests {
    private static let keyword: UInt32 = 0x10
    private static let refType: UInt32 = 0x12
    private static let linker: UInt32 = 0x50
    private static let linked: UInt32 = 0x51
    private static let other: UInt32 = 0x52

    private static func context() throws -> ConditionContext {
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "KYWD", contents: KeywordFixture.recordBytes(formID: keyword, editorID: "LinkTag")
        ))
        let index = RecordIndex(plugins: [("Test.esm", file)], recordTypes: ["KYWD"])
        let fields = ESMFixture.field("NAME", ESMFixture.words([0x40]))
            + ESMFixture.field("DATA", Data(count: 24))
            + ESMFixture.field("XLKR", ESMFixture.words([keyword, linked]))
            + ESMFixture.field("XLKR", ESMFixture.words([other]))
            + ESMFixture.field("XLRT", ESMFixture.words([refType]))
        let record = try ESMFixture.parseRecord(
            ESMFixture.record("REFR", formID: linker, data: fields)
        )
        let key = ConditionEvaluatorFixture.key(linker, plugin: "test.esm")
        var context = ConditionContext()
        context.references = try RuntimeReferenceIndex(entries: [RuntimeReferenceEntry(
            key: key, formID: FormID(linker), isPersistent: true,
            record: .reference(PlacedReference(record: record))
        )])
        context.subject = key
        context.data = ConditionDataResolution(
            keywords: KeywordStore(index: index), sourcePlugin: "Test.esm"
        )
        return context
    }

    private static func evaluate(
        _ function: UInt16,
        equals value: Float,
        _ parameter1: UInt32,
        _ parameter2: UInt32 = 0
    ) throws -> ConditionOutcome {
        var evaluator = try ConditionEvaluator(context: context())
        return try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: function,
            parameter1: parameter1, parameter2: parameter2
        ))
    }

    @Test func hasLinkedRefMatchesTheKeyword() throws {
        #expect(try Self.evaluate(362, equals: 1, Self.keyword) == .true)
        #expect(try Self.evaluate(362, equals: 1, 0) == .true)
        #expect(try Self.evaluate(362, equals: 0, 0x0FFF) == .true)
    }

    @Test func isLinkedToMatchesTheReferenceUnderTheKeyword() throws {
        #expect(try Self.evaluate(650, equals: 1, Self.linked, Self.keyword) == .true)
        #expect(try Self.evaluate(650, equals: 0, Self.linked) == .true)
        #expect(try Self.evaluate(650, equals: 1, Self.other) == .true)
    }

    @Test func hasRefTypeReadsXLRT() throws {
        #expect(try Self.evaluate(561, equals: 1, Self.refType) == .true)
        #expect(try Self.evaluate(561, equals: 0, 0x13) == .true)
    }
}
