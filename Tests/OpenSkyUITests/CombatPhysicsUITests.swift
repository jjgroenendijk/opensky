// World > Combat & Physics UI test, its own case for the type-length cap. Unit
// tests pin the ids; only a UI test proves they are reachable.

import XCTest

final class CombatPhysicsUITests: OpenSkyUITestCase {
    /// The sidebar lists World > Combat & Physics, and selecting it shows every
    /// gate control and the six readouts they change.
    @MainActor
    func testCombatPhysicsControlsAndReadouts() throws {
        let app = try launchApp()
        selectDestination("Destination-combatPhysics", in: app)

        XCTAssertTrue(
            app.popUpButtons["ActorValueTargetControl"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.popUpButtons["ActorValueKindControl"].exists)
        XCTAssertTrue(app.textFields["ActorValueNameControl"].exists)
        XCTAssertTrue(app.textFields["ActorValueAmountControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueDamageControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueSetControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueSetBaseControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueRestoreControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueRefillControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueResetControl"].exists)
        XCTAssertTrue(app.checkBoxes["MeleeWeaponDrawnControl"].exists)
        XCTAssertTrue(app.buttons["MeleeAttackControl"].exists)
        XCTAssertTrue(app.buttons["ArcherySpawnControl"].exists)
        XCTAssertTrue(app.buttons["RagdollTriggerControl"].exists)
        XCTAssertTrue(app.checkBoxes["CombatHostilityControl"].exists)
        XCTAssertTrue(app.checkBoxes["CombatActorCastingControl"].exists)
        XCTAssertTrue(app.buttons["CombatClearTraceControl"].exists)
        XCTAssertTrue(app.checkBoxes["PhysicsFreezeControl"].exists)
        XCTAssertTrue(app.buttons["PhysicsResetControl"].exists)

        for readout in [
            "CombatActorValuesStatsLabel", "CombatMeleeStatsLabel",
            "CombatArcheryStatsLabel", "CombatRagdollStatsLabel",
            "CombatLoopStatsLabel", "CombatPhysicsStatsLabel"
        ] {
            XCTAssertTrue(app.staticTexts[readout].exists, readout)
        }
    }
}
