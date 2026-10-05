// The idle selector over synthetic IDLE records: marker order, do-once, the
// related-idle tree, and the trace for every candidate.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct IdleSelectorTests {
    private static func idle(_ objectID: UInt32, _ editorID: String, event: String? = nil)
        throws -> ResolvedRecord<IdleAnimation>
    {
        var fields = [("EDID", ESMFixture.zstring(editorID))]
        if let event {
            fields.append(("ENAM", ESMFixture.zstring(event)))
        }
        return try ResolvedRecord(
            id: ResolvedFormID(plugin: "Test.esm", objectID: objectID),
            record: IdleAnimation(record: ESMFixture.record(
                "IDLE",
                formID: objectID,
                fields: fields
            )),
            sourcePlugin: "Test.esm"
        )
    }

    /// Fails every idle whose editor ID is in `failing`, naming `GetIsID`.
    private static func selector(
        failing: Set<String> = [],
        children: [UInt32: [ResolvedRecord<IdleAnimation>]] = [:]
    ) -> IdleSelector {
        IdleSelector(
            children: { children[$0.objectID] ?? [] },
            check: { failing.contains($0.editorID ?? "") ? "GetIsID" : nil }
        )
    }

    @Test func aSequenceMarkerTakesTheFirstPassingEntryFromItsNextIndex() throws {
        let entries = try [
            Self.idle(1, "Lean", event: "IdleLean"),
            Self.idle(2, "Pray", event: "IdlePray"),
            Self.idle(3, "Wipe", event: "IdleWipeBrow")
        ]
        let selection = Self.selector(failing: ["Pray"]).select(
            entries: entries, order: .sequence, startIndex: 1, played: [], random: { _ in 0 }
        )
        #expect(selection.chosen?.record.editorID == "Wipe")
        #expect(selection.chosenEntry == 2)
        #expect(selection.trace.map(\.verdict) == [.rejected("GetIsID"), .chosen, .notReached])
        #expect(selection.trace.map(\.editorID) == ["Pray", "Wipe", "Lean"])
    }

    @Test func aRandomMarkerPicksAmongPassingEntriesAndSkipsPlayedOnes() throws {
        let entries = try [
            Self.idle(1, "Lean", event: "IdleLean"),
            Self.idle(2, "Pray", event: "IdlePray"),
            Self.idle(3, "Wipe", event: "IdleWipeBrow")
        ]
        var asked: [Int] = []
        let selection = Self.selector().select(
            entries: entries, order: .random, startIndex: 0,
            played: [entries[0].id], random: { asked.append($0)
                return 1
            }
        )
        #expect(asked == [2])
        #expect(selection.chosen?.record.editorID == "Wipe")
        #expect(selection.trace.map(\.verdict) == [.alreadyPlayed, .passed, .chosen])
    }

    @Test func nothingPassesGivesNoChoiceAndAFullTrace() throws {
        let entries = try [Self.idle(1, "Lean", event: "IdleLean")]
        let selection = Self.selector(failing: ["Lean"]).select(
            entries: entries, order: .random, startIndex: 0, played: [], random: { _ in 0 }
        )
        #expect(selection.chosen == nil)
        #expect(selection.chosenEntry == nil)
        #expect(selection.trace.map(\.verdict) == [.rejected("GetIsID")])
    }

    @Test func aTreeDescendsToTheDeepestPassingChild() throws {
        let group = try Self.idle(10, "Chores")
        let sweep = try Self.idle(11, "Sweep", event: "IdleSweep")
        let hoe = try Self.idle(12, "Hoe", event: "IdleHoe")
        let other = try Self.idle(20, "Other", event: "IdleOther")
        let selection = Self.selector(failing: ["Sweep"], children: [10: [sweep, hoe]])
            .select(roots: [group, other])
        #expect(selection.chosen?.record.editorID == "Hoe")
        #expect(selection.trace.map(\.editorID) == ["Chores", "Sweep", "Hoe", "Other"])
        #expect(selection.trace.map(\.depth) == [0, 1, 1, 0])
        #expect(selection.trace.map(\.verdict) == [
            .passed, .rejected("GetIsID"), .chosen, .notReached
        ])
    }

    @Test func aGroupWithoutAnEventOrAPassingChildIsSkipped() throws {
        let group = try Self.idle(10, "Chores")
        let sweep = try Self.idle(11, "Sweep", event: "IdleSweep")
        let lean = try Self.idle(20, "Lean", event: "IdleLean")
        let selection = Self.selector(failing: ["Sweep"], children: [10: [sweep]])
            .select(roots: [group, lean])
        #expect(selection.chosen?.record.editorID == "Lean")
        #expect(selection.trace.map(\.verdict) == [.noAnimation, .rejected("GetIsID"), .chosen])
    }

    @Test func aFailedParentLeavesItsChildrenUnreached() throws {
        let group = try Self.idle(10, "Chores", event: "IdleChores")
        let sweep = try Self.idle(11, "Sweep", event: "IdleSweep")
        let selection = Self.selector(failing: ["Chores"], children: [10: [sweep]])
            .select(roots: [group])
        #expect(selection.chosen == nil)
        #expect(selection.trace.map(\.verdict) == [.rejected("GetIsID"), .notReached])
    }
}
