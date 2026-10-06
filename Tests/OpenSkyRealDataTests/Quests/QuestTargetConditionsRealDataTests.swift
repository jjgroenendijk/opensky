// Quest target conditions on the real install. `MQ105Ustengrav` objective 20 has
// two targets split on the stage of the quest its conditions name, so exactly one
// shows at each stage. See docs/engine/world-map.md.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorld
import Testing

struct QuestTargetConditionsRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func onlyThePassingUstengravTargetShows() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let quests = QuestStore(file: file, pluginName: "Skyrim.esm")
        let quest = try #require(quests.quest(editorID: "MQ105Ustengrav"))
        let objective = try #require(quest.objectives.first { $0.index == 20 })
        try #require(objective.targets.count == 2)
        let condition = try #require(objective.targets.first?.conditions.conditions.first)
        let gate = condition.parameter1.asFormID
        let gateKey = try #require(quests.key(for: gate))

        func shown(atStage stage: UInt16) -> [Int32] {
            let state = QuestRuntimeState(isRunning: true, stagesReached: [stage])
            let context = ConditionContext(
                quests: QuestResolution(defaults: quests, overrides: [gateKey: state])
            )
            return objective.targets.filter { target in
                QuestTargetResolver.conditionsPass(
                    target, quest: quest.formID, evaluator: ConditionEvaluator(context: context)
                ) { _ in nil }
            }.map(\.aliasID)
        }

        let early = shown(atStage: 0)
        let late = shown(atStage: 10)
        #expect(early.count == 1)
        #expect(late.count == 1)
        #expect(early != late)
    }
}
