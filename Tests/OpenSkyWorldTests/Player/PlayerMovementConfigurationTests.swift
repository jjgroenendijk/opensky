// Player movement tuning resolved from GMST game settings. In-code plugin fixtures only.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorld
import Testing

struct PlayerMovementConfigurationTests {
    @Test
    func movementResolutionUsesValidFloatsAndExplicitFallbacks() throws {
        let file = try GameSettingFixture.plugin(
            editorID: "fMoveCharWalkBase",
            value: 125,
            formID: 1
        )
        let configuration = PlayerMovementConfiguration.resolve(
            store: GameSettingStore(plugins: [("Tuning.esp", file)])
        )
        #expect(configuration.walkSpeed == MovementSetting(value: 125, source: "Tuning.esp"))
        #expect(configuration.runSpeed == MovementSetting(value: 370, source: "engine default"))
        #expect(configuration.stepHeight.value == 32)
        #expect(configuration.stepHeight.source.contains("no confirmed"))
    }
}
