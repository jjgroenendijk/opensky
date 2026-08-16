// World > Combat & Physics UI surface (issue #198, roadmap item 15.9), in its
// own case rather than in `OpenSkyUITests` for the strict-lint type-length cap.
//
// The id contract is pinned in `DestinationRegistryTests` and
// `CombatPhysicsPanelTests` as well; only a UI test proves the ids are
// reachable in the built view hierarchy, which is the gap issue #380 recorded.

import XCTest

final class CombatPhysicsUITests: OpenSkyUITestCase {
    /// World > Combat & Physics acceptance surface (M15, issue #198): the
    /// sidebar lists the destination the milestone gate names, and selecting it
    /// exposes every control the gate drives together with the six readouts
    /// they change. Pinned here as well as in `DestinationRegistryTests`
    /// because only a UI test proves the ids are reachable in the built view
    /// hierarchy (issue #380).
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
        XCTAssertTrue(app.buttons["ActorValueRestoreControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueRefillControl"].exists)
        XCTAssertTrue(app.buttons["ActorValueResetControl"].exists)
        XCTAssertTrue(app.checkBoxes["MeleeWeaponDrawnControl"].exists)
        XCTAssertTrue(app.buttons["MeleeAttackControl"].exists)
        XCTAssertTrue(app.buttons["ArcherySpawnControl"].exists)
        XCTAssertTrue(app.buttons["RagdollTriggerControl"].exists)
        XCTAssertTrue(app.checkBoxes["CombatHostilityControl"].exists)
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
