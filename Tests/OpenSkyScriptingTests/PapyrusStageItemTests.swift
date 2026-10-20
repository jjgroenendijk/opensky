// A stage runs the fragment of every item whose conditions pass, not only the first.

import Foundation
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusStageItemTests {
    private static func quest(firstItemConditioned: Bool) throws -> Quest {
        var fields = QuestFixture.editorID("StageItems")
        fields += QuestFixture.stage(10)
        fields += QuestFixture.logEntry()
        if firstItemConditioned {
            fields += QuestFixture.condition(functionIndex: 74)
        }
        fields += QuestFixture.logEntry()
        return try QuestFixture.quest(fields: fields)
    }

    @Test func everyPassingItemIsChosen() throws {
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        let quest = try Self.quest(firstItemConditioned: true)
        #expect(bridge.passingItems(of: quest, stage: 10) == nil)
        bridge.sessionNatives.conditionEvaluator = {
            ConditionEvaluator(context: ConditionContext(), registry: .empty)
        }
        #expect(bridge.passingItems(of: quest, stage: 10) == [1])
        let open = try Self.quest(firstItemConditioned: false)
        #expect(bridge.passingItems(of: open, stage: 10) == [0, 1])
    }
}
