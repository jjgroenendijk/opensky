// GetIsObjectType reads the record type of the run-on's base form, with xEdit's
// `wbFormTypeEnum` as the parameter.

import Foundation
@testable import OpenSkyConditions
import OpenSkyFeaturesTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldState
import Testing

struct ConditionObjectTypeFunctionTests {
    private static let door: UInt32 = 0x40
    private static let placed: UInt32 = 0x50

    private static func evaluate(_ type: UInt32, equals value: Float, player: Bool = false) throws
        -> ConditionOutcome
    {
        let file = try ESMFile(data: ESMFixture.tes4() + ESMFixture.topGroup(
            "DOOR", contents: ESMFixture.record("DOOR", formID: door, data: Data())
        ))
        let index = RecordIndex(plugins: [("Test.esm", file)], recordTypes: ["DOOR"])
        let fields = ESMFixture.field("NAME", ESMFixture.words([door]))
            + ESMFixture.field("DATA", Data(count: 24))
        let record = try ESMFixture.parseRecord(
            ESMFixture.record("REFR", formID: placed, data: fields)
        )
        let key = ConditionEvaluatorFixture.key(placed, plugin: "test.esm")
        var context = ConditionContext()
        context.references = try RuntimeReferenceIndex(entries: [RuntimeReferenceEntry(
            key: key, formID: FormID(placed), isPersistent: true,
            record: .reference(PlacedReference(record: record))
        )])
        context.subject = player ? .player : key
        context.data = ConditionDataResolution(
            keywords: KeywordStore(index: index), sourcePlugin: "Test.esm"
        )
        var evaluator = ConditionEvaluator(context: context)
        return try evaluator.evaluate(ConditionEvaluatorFixture.condition(
            comparisonValue: value.bitPattern, functionIndex: 432, parameter1: type
        ))
    }

    @Test func theBaseRecordTypeAnswers() throws {
        #expect(try Self.evaluate(4, equals: 1) == .true)
        #expect(try Self.evaluate(3, equals: 0) == .true)
        #expect(try Self.evaluate(13, equals: 1, player: true) == .true)
        #expect(try Self.evaluate(11, equals: 0).failures == [.unresolvedParameter(432)])
    }
}
