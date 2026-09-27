// Synthetic coverage for the fourteen M18 data condition functions (issue
// #455). Every CTDA and record byte is built in code; no game data is used.

import Foundation
@testable import opensky
import Testing

@MainActor
@Suite("Keyword, form-list and location condition functions")
struct ConditionFunctionsDataTests {
    private enum FixtureID {
        static let keyword: UInt32 = 0x10
        static let otherKeyword: UInt32 = 0x11
        static let parentLocation: UInt32 = 0x20
        static let childLocation: UInt32 = 0x21
        static let otherLocation: UInt32 = 0x22
        static let siblingLocation: UInt32 = 0x23
        static let outerList: UInt32 = 0x30
        static let innerList: UInt32 = 0x31
        static let emptyList: UInt32 = 0x32
        static let subjectBase: UInt32 = 0x40
        static let targetBase: UInt32 = 0x41
        static let subjectReference: UInt32 = 0x50
        static let targetReference: UInt32 = 0x51
        static let quest: UInt32 = 0x100
    }

    private struct Fixture {
        let keywords: KeywordStore
        let formLists: FormListStore
        let locations: LocationStore
        let aliases: QuestAliasResolution
        let references: RuntimeReferenceIndex

        func context(related: Bool = true) -> ConditionContext {
            let subject = key(FixtureID.subjectReference)
            let target = key(FixtureID.targetReference)
            let subjectLocation = resolved(
                related ? FixtureID.childLocation : FixtureID.otherLocation
            )
            let targetLocation = resolved(FixtureID.siblingLocation)
            let data = ConditionDataResolution(
                keywords: keywords,
                formLists: formLists,
                locations: locations,
                sourcePlugin: "Test.esm",
                currentLocations: [
                    subject: subjectLocation,
                    target: targetLocation
                ],
                editorLocations: [
                    subject: subjectLocation,
                    target: targetLocation
                ]
            )
            return ConditionContext(
                aliases: aliases,
                data: data,
                aliasQuest: FormID(FixtureID.quest),
                references: references,
                subject: subject,
                target: target
            )
        }

        private func key(_ raw: UInt32) -> ReferenceKey {
            ConditionEvaluatorFixture.key(raw, plugin: "test.esm")
        }

        private func resolved(_ raw: UInt32) -> ResolvedFormID {
            ResolvedFormID(plugin: "Test.esm", objectID: raw)
        }
    }

    private struct DataCase {
        let index: UInt16
        let parameter1: UInt32
        let parameter2: UInt32
        let falseParameter1: UInt32?
        let falseParameter2: UInt32?
        let falseUsesUnrelatedContext: Bool

        init(
            _ index: UInt16,
            _ parameter1: UInt32,
            _ parameter2: UInt32 = 0,
            falseParameter1: UInt32? = nil,
            falseParameter2: UInt32? = nil,
            falseUsesUnrelatedContext: Bool = false
        ) {
            self.index = index
            self.parameter1 = parameter1
            self.parameter2 = parameter2
            self.falseParameter1 = falseParameter1
            self.falseParameter2 = falseParameter2
            self.falseUsesUnrelatedContext = falseUsesUnrelatedContext
        }
    }

    private var cases: [DataCase] {
        [
            DataCase(560, FixtureID.keyword, falseParameter1: FixtureID.otherKeyword),
            DataCase(372, FixtureID.outerList, falseParameter1: FixtureID.emptyList),
            DataCase(359, FixtureID.parentLocation, falseParameter1: FixtureID.otherLocation),
            DataCase(565, FixtureID.parentLocation, falseParameter1: FixtureID.otherLocation),
            DataCase(444, FixtureID.outerList, falseParameter1: FixtureID.emptyList),
            DataCase(562, FixtureID.keyword, falseParameter1: FixtureID.otherKeyword),
            DataCase(360, 0, falseUsesUnrelatedContext: true),
            DataCase(567, 0, falseUsesUnrelatedContext: true),
            DataCase(605, 0, FixtureID.parentLocation, falseParameter2: FixtureID.otherLocation),
            DataCase(610, 0, FixtureID.keyword, falseParameter2: FixtureID.otherKeyword),
            DataCase(
                180,
                FixtureID.targetReference,
                FixtureID.keyword,
                falseUsesUnrelatedContext: true
            ),
            DataCase(181, 1, FixtureID.keyword, falseUsesUnrelatedContext: true),
            DataCase(
                603,
                FixtureID.targetReference,
                FixtureID.keyword,
                falseUsesUnrelatedContext: true
            ),
            DataCase(604, 1, FixtureID.keyword, falseUsesUnrelatedContext: true)
        ]
    }

    @Test func everyMeasuredFunctionHasTrueAndFalsePaths() throws {
        let fixture = try makeFixture()
        for item in cases {
            let positive = try evaluate(item, context: fixture.context())
            #expect(positive.isTrue, "raw index \(item.index) did not return true")
            #expect(positive.isConclusive)

            let negative = DataCase(
                item.index,
                item.falseParameter1 ?? item.parameter1,
                item.falseParameter2 ?? item.parameter2
            )
            let context = fixture.context(related: !item.falseUsesUnrelatedContext)
            let outcome = try evaluate(negative, context: context)
            #expect(!outcome.isTrue, "raw index \(item.index) did not return false")
            #expect(outcome.isConclusive, "raw index \(item.index) false was unavailable")
        }
    }

    @Test func everyMeasuredFunctionDistinguishesUnavailableFromFalse() throws {
        for item in cases {
            let outcome = try evaluate(item, context: ConditionContext())
            #expect(!outcome.isTrue)
            #expect(!outcome.isConclusive, "raw index \(item.index) hid unavailable data")
            #expect(!outcome.failures.isEmpty)
        }
    }

    @Test func nestedListAndInheritedLocationKeywordAreExercised() throws {
        let fixture = try makeFixture()
        let list = try evaluate(cases[1], context: fixture.context())
        let locationKeyword = try evaluate(cases[5], context: fixture.context())
        let aliasKeyword = try evaluate(cases[9], context: fixture.context())

        #expect(list.isTrue)
        #expect(locationKeyword.isTrue)
        #expect(aliasKeyword.isTrue)
        let child = try #require(fixture.locations.location(resolved(FixtureID.childLocation)))
        #expect(!child.location.keywords.keywords.contains(FormID(FixtureID.keyword)))
    }

    @Test func danglingFormIDsAreUnavailableRatherThanFalse() throws {
        let context = try makeFixture().context()
        let cases = [
            DataCase(560, 0xDEAD),
            DataCase(372, 0xDEAD),
            DataCase(359, 0xDEAD)
        ]
        let failures = try cases.map { try evaluate($0, context: context).failures }

        #expect(failures == [
            [.unavailableData(.keyword)],
            [.unavailableData(.formList)],
            [.unavailableData(.location)]
        ])
    }

    private func evaluate(
        _ item: DataCase,
        context: ConditionContext
    ) throws -> ConditionOutcome {
        let condition = try ConditionEvaluatorFixture.condition(
            comparisonValue: Float(1).bitPattern,
            functionIndex: item.index,
            parameter1: item.parameter1,
            parameter2: item.parameter2
        )
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition)
    }

    private func makeFixture() throws -> Fixture {
        let file = try ESMFile(data: pluginData())
        let index = RecordIndex(
            plugins: [("Test.esm", file)],
            recordTypes: ["KYWD", "FLST", "LCTN", "MISC"]
        )
        let locations = LocationStore(index: index)
        let runtime = try aliasRuntime(locations: locations)
        try runtime.startQuest(FormID(FixtureID.quest))
        return try Fixture(
            keywords: KeywordStore(index: index),
            formLists: FormListStore(index: index),
            locations: locations,
            aliases: runtime.aliasResolution(),
            references: ConditionEvaluatorFixture.references([
                (formID: FixtureID.subjectReference, base: FixtureID.subjectBase),
                (formID: FixtureID.targetReference, base: FixtureID.targetBase)
            ], plugin: "test.esm")
        )
    }

    private func aliasRuntime(locations: LocationStore) throws -> QuestRuntime {
        let aliases = QuestFixture.alias(
            id: 0,
            name: "Place",
            location: true,
            fill: QuestFixture.word("ALFL", FixtureID.parentLocation)
        ) + QuestFixture.alias(
            id: 1,
            name: "OtherReference",
            fill: QuestFixture.word("ALFR", FixtureID.targetReference)
        )
        return try QuestRuntime(
            store: WorldStateStore(),
            quests: QuestFixture.store(QuestFixture.record(
                formID: FixtureID.quest,
                fields: QuestFixture.editorID("DataConditions") + aliases
            )),
            locations: locations
        )
    }
}

@MainActor
extension ConditionFunctionsDataTests {
    private func pluginData() -> Data {
        ESMFixture.tes4()
            + ESMFixture.topGroup("KYWD", contents: keywordRecords())
            + ESMFixture.topGroup("FLST", contents: formListRecords())
            + ESMFixture.topGroup("LCTN", contents: locationRecords())
            + ESMFixture.topGroup("MISC", contents: baseRecords())
    }

    private func keywordRecords() -> Data {
        keyword(FixtureID.keyword, "LocTypeTest") + keyword(FixtureID.otherKeyword, "OtherKeyword")
    }

    private func keyword(_ formID: UInt32, _ editorID: String) -> Data {
        ESMFixture.record(
            "KYWD",
            formID: formID,
            data: ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        )
    }

    private func formListRecords() -> Data {
        list(FixtureID.innerList, "Inner", [FixtureID.subjectBase, FixtureID.parentLocation])
            + list(FixtureID.outerList, "Outer", [FixtureID.innerList])
            + list(FixtureID.emptyList, "Empty", [])
    }

    private func list(_ formID: UInt32, _ editorID: String, _ entries: [UInt32]) -> Data {
        FormListTests.recordBytes(formID: formID, editorID: editorID, entries: entries)
    }

    private func locationRecords() -> Data {
        location(FixtureID.parentLocation, "Parent", keywords: [FixtureID.keyword])
            + location(FixtureID.childLocation, "Child", parent: FixtureID.parentLocation)
            + location(FixtureID.siblingLocation, "Sibling", parent: FixtureID.parentLocation)
            + location(FixtureID.otherLocation, "Other", keywords: [FixtureID.keyword])
    }

    private func location(
        _ formID: UInt32,
        _ editorID: String,
        parent: UInt32? = nil,
        keywords: [UInt32] = []
    ) -> Data {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let parent {
            fields += ESMFixture.field("PNAM", words([parent]))
        }
        if !keywords.isEmpty {
            fields += ESMFixture.field("KSIZ", words([UInt32(keywords.count)]))
                + ESMFixture.field("KWDA", words(keywords))
        }
        return ESMFixture.record("LCTN", formID: formID, data: fields)
    }

    private func baseRecords() -> Data {
        ESMFixture.record(
            "MISC",
            formID: FixtureID.subjectBase,
            data: ESMFixture.field("KSIZ", words([1]))
                + ESMFixture.field("KWDA", words([FixtureID.keyword]))
        ) + ESMFixture.record("MISC", formID: FixtureID.targetBase, data: Data())
    }

    private func words(_ values: [UInt32]) -> Data {
        var data = Data()
        for value in values {
            data.appendUInt32(value)
        }
        return data
    }

    private func resolved(_ raw: UInt32) -> ResolvedFormID {
        ResolvedFormID(plugin: "Test.esm", objectID: raw)
    }
}
