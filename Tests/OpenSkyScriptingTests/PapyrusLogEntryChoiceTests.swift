// A stage runs only the fragment of its first log entry whose conditions pass.

import Foundation
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusLogEntryChoiceTests {
    private static func quest(firstEntryConditioned: Bool) throws -> Quest {
        var fields = QuestFixture.editorID("LogEntryChoice")
        fields += QuestFixture.stage(10)
        fields += QuestFixture.logEntry()
        if firstEntryConditioned {
            fields += QuestFixture.condition(functionIndex: 74)
        }
        fields += QuestFixture.logEntry()
        return try QuestFixture.quest(fields: fields)
    }

    @Test func theFirstPassingEntryIsChosen() throws {
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        let quest = try Self.quest(firstEntryConditioned: true)
        #expect(bridge.chosenLogEntry(of: quest, stage: 10) == nil)
        bridge.logEntryEvaluator = {
            ConditionEvaluator(context: ConditionContext(), registry: .empty)
        }
        #expect(bridge.chosenLogEntry(of: quest, stage: 10) == 1)
        let open = try Self.quest(firstEntryConditioned: false)
        #expect(bridge.chosenLogEntry(of: open, stage: 10) == 0)
    }

    @Test func theChosenEntrysCompleteFlagCompletesTheQuest() throws {
        var fields = QuestFixture.editorID("LogEntryComplete")
        fields += QuestFixture.stage(10)
        fields += QuestFixture.logEntry()
        fields += QuestFixture.logEntry(flags: 1)
        let quest = try QuestFixture.quest(fields: fields)
        #expect(PapyrusWorldStateBridge.completes(quest, stage: 10, logEntry: 1))
        #expect(!PapyrusWorldStateBridge.completes(quest, stage: 10, logEntry: 0))
        #expect(!PapyrusWorldStateBridge.completes(quest, stage: 10, logEntry: nil))
        #expect(!PapyrusWorldStateBridge.completes(quest, stage: 10, logEntry: -1))
    }
}
