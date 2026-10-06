// Which objective targets reach the map: shown, unfinished, and passing QSTA.

import FormatsTesting
import OpenSkyFormatsESM
import OpenSkyMenus
import OpenSkyQuestsInterface
import Testing

struct QuestTargetRequestTests {
    private static func quest() throws -> Quest {
        try QuestFixture.quest(
            formID: 0x10,
            fields: QuestFixture.objective(10) + QuestFixture.target(alias: 1)
                + QuestFixture.target(alias: 2) + QuestFixture.objective(20)
                + QuestFixture.target(alias: 1)
        )
    }

    @Test
    func onlyShownObjectivesAskAndFailedConditionsHide() throws {
        let state = QuestRuntimeState(
            isRunning: true, objectives: [QuestObjectiveState(index: 10, isDisplayed: true)]
        )
        var asked: [Int32] = []
        let requests = try QuestTargetResolver.requests(
            quest: Self.quest(), state: state, text: { "Objective \($0.index)" },
            conditionsPass: { target in
                asked.append(target.aliasID)
                return target.aliasID == 1
            }
        )
        #expect(asked == [1, 2])
        #expect(requests.map(\.aliasID) == [1, 2])
        #expect(requests.map(\.conditionsPass) == [true, false])
        let markers = QuestTargetResolver.resolve(
            requests,
            alias: { _, alias in
                ReferenceKey(resolved: ResolvedFormID(
                    plugin: "Skyrim.esm",
                    objectID: UInt32(alias)
                ))
            },
            place: { _ in .placed(position: SIMD3(0, 0, 0), cell: nil) }
        )
        #expect(markers.map(\.anchor) == [ReferenceKey(resolved: ResolvedFormID(
            plugin: "Skyrim.esm",
            objectID: 1
        ))])
    }

    @Test
    func aCompletedObjectiveShowsNoTarget() throws {
        let state = QuestRuntimeState(
            isRunning: true,
            objectives: [QuestObjectiveState(index: 10, isDisplayed: true, isCompleted: true)]
        )
        let requests = try QuestTargetResolver.requests(
            quest: Self.quest(), state: state, text: { _ in "" }, conditionsPass: { _ in true }
        )
        #expect(requests.isEmpty)
    }
}
