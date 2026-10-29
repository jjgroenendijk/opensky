// `hkbClipGenerator` members a variable binding sets in place of the authored value.

import Foundation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorClipBindingTests {
    private let tolerance: Float = 0.01

    @Test func aBoundStartTimeWinsOverTheAuthoredOne() throws {
        let data = BehaviorFixture.graphData(
            variables: [BehaviorVariableSpec("attackIntroLength", .real, 0)]
        )
        var table = BehaviorObjectTable()
        let binding = table.add(
            BehaviorFixture.bindingSet([BehaviorBindingSpec("m_startTime", 0)]), at: 0x80
        )
        let root = table.add(
            BehaviorFixture.clipGenerator(
                "walk", animationName: "walk", startTime: 0.5, bindingSet: binding
            ),
            at: 0x100
        )
        let graph = try BehaviorFixture.instance(
            root: root, table: table, data: data,
            clips: BehaviorClipTable(byName: ["walk": BehaviorFixture.splineClip()])
        )
        // Seeded at the bound 0, not the authored 0.5, then advanced by the step.
        #expect(abs(graph.update(deltaTime: 0.1).bones[1].translation.x - 3) < tolerance)
    }
}
