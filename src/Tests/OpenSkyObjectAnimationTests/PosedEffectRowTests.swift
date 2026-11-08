// The row `game state effects` prints for one posed effect model.

import OpenSkyWorldInterface
import Testing

struct PosedEffectRowTests {
    @Test func aRowKeepsItsEffectModelAndBones() {
        let row = PosedEffectRow(effectID: 3, modelPath: "magic/flames.nif", bones: ["Root", "Tip"])
        #expect(row.effectID == 3)
        #expect(row.modelPath == "magic/flames.nif")
        #expect(row.bones == ["Root", "Tip"])
        #expect(row != PosedEffectRow(effectID: 4, modelPath: "magic/flames.nif", bones: []))
    }
}
