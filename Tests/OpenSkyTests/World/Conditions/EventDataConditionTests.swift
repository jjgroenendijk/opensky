// GetEventData (576) and the Event Data run-on (7), over a story event. Each
// condition is a real 32-byte CTDA; member codes are xEdit `wbEventMemberEnum`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct EventDataConditionTests {
    private typealias Fixture = ConditionEvaluatorFixture
    private let keyword = FormID(0x0000_0A00)

    private var subject: ReferenceKey {
        Fixture.key(Fixture.subjectFormID)
    }

    private func outcome(
        _ condition: Condition,
        event: StoryEventData?
    ) throws -> ConditionOutcome {
        var context = try ConditionContext(
            references: Fixture.references([(
                formID: Fixture.subjectFormID,
                base: Fixture.subjectBase
            )])
        )
        context.event = event
        var evaluator = ConditionEvaluator(context: context)
        return evaluator.evaluate(condition)
    }

    /// `GetEventData(function | member << 16, form) == value`.
    private func eventData(
        function: UInt32,
        _ member: StoryEventData.Member,
        form: UInt32 = 0,
        equals value: Float = 1
    ) throws -> Condition {
        try Fixture.condition(
            comparisonValue: value.bitPattern, functionIndex: 576,
            parameter1: function | UInt32(member.rawValue) << 16, parameter2: form
        )
    }

    private var event: StoryEventData {
        var event = StoryEventData(event: "SCPT")
        event.actor1 = subject
        event.keyword = keyword
        event.value1 = 5
        return event
    }

    @Test func getValueReadsTheEventValue() throws {
        #expect(try outcome(eventData(function: 2, .value1, equals: 5), event: event).isTrue)
        #expect(try !outcome(eventData(function: 2, .value1, equals: 4), event: event).isTrue)
    }

    @Test func hasKeywordComparesTheEventKeyword() throws {
        #expect(try outcome(eventData(function: 3, .keyword, form: 0x0A00), event: event).isTrue)
        #expect(try !outcome(eventData(function: 3, .keyword, form: 0x0A01), event: event).isTrue)
    }

    @Test func getIsIDComparesAReferenceMembersBase() throws {
        let condition = try eventData(function: 0, .actor1, form: Fixture.subjectBase)
        #expect(try outcome(condition, event: event).isTrue)
    }

    @Test func withoutAnEventTheCallFails() throws {
        #expect(try !outcome(eventData(function: 2, .value1, equals: 0), event: nil).isTrue)
    }

    /// Run-on 7 runs the function on the member parameter 3 names.
    @Test func theEventDataRunOnReadsAMember() throws {
        let condition = try Fixture.condition(
            comparisonValue: Float(1).bitPattern, functionIndex: 72,
            parameter1: Fixture.subjectBase, runOn: 7,
            parameter3: Int32(StoryEventData.Member.actor1.rawValue)
        )
        #expect(try outcome(condition, event: event).isTrue)
        var other = event
        other.actor1 = nil
        other.actor2 = subject
        #expect(try !outcome(condition, event: other).isTrue)
    }
}
