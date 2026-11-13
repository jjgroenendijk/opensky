// A theft's skill use: the stack value to the power of `fPickpocketSkillUsesCurve`.

import Foundation
import OpenSkyGameData
import Testing

struct PickpocketSkillUseTests {
    @Test func theStackValueIsRaisedToTheCurve() {
        let settings = PickpocketSettings.vanilla
        #expect(abs(settings.skillUse(stackValue: 100) - pow(100, 0.8)) < 0.001)
        // A worthless item still counts as value 1.
        #expect(settings.skillUse(stackValue: 0) == 1)
    }
}
