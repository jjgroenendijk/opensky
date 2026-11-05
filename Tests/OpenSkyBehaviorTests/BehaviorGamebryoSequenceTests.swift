// A `BGSGamebryoSequenceGenerator` names the NIF sequence its graph's own mesh plays,
// such as `mCharge` on a hand effect.

import Foundation
import OpenSkyBehavior
import OpenSkyEngineTesting
@testable import OpenSkyFormatsAnimation
import Testing

struct BehaviorGamebryoSequenceTests {
    @Test func aReachedSequenceGeneratorIsRecordedForItsStep() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BGSGamebryoSequenceGenerator(
                node: BehaviorFixture.nodeHeader("mChargeSequence"),
                sequence: "mCharge", blendModeFunction: 0, percent: 1, unresolved: []
            ),
            at: 0x100
        )
        let graph = BehaviorFixture.instance(root: root, table: table)
        #expect(graph.gamebryoSequences.isEmpty)
        graph.update(deltaTime: 1 / 30)
        #expect(graph.gamebryoSequences == ["mCharge"])
        graph.deactivate()
        #expect(graph.gamebryoSequences.isEmpty)
    }
}
