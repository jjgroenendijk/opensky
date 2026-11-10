import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkySessionTesting
import Testing

// Each port answers for the object behind it, so an adapter asks one port, not a chain of them.

@MainActor
struct PortShortcutTests {
    @Test func combatReadsArcheryAndMeleeOnlyOnceTheyStart() {
        let combat = FakeCombatPort()
        #expect(combat.liveProjectiles.isEmpty)
        #expect(combat.projectileImpacts == nil)
        #expect(combat.removeArrows(stuckIn: FormID(0x14)) == 0)
        #expect(combat.meleeWeaponInHand == nil)

        let archery = FakeArcheryRuntimePort()
        archery.projectiles.removeArrowsResult = 3
        combat.archery = archery
        let melee = FakeMeleeCombatRuntimePort()
        melee.state.drawStateValue = .drawn
        combat.melee = melee
        #expect(combat.removeArrows(stuckIn: FormID(0x14)) == 3)
        #expect(archery.projectiles.removeArrowsCalls == [FormID(0x14)])
        #expect(combat.liveProjectiles.isEmpty)
        #expect(combat.projectileImpacts == nil)
        #expect(combat.meleeWeaponInHand == true)
    }

    @Test func scriptsAnswerAWaitOnlyWithARunningWorld() {
        let scripts = FakeScriptPort()
        #expect(!scripts.answer(7, returning: .none))
        let runtime = FakePapyrusWorldRuntimePort()
        runtime.scheduler.answerResult = true
        scripts.runtime = runtime
        #expect(scripts.answer(7, returning: .none))
        #expect(runtime.scheduler.answerCalls.map(\.token) == [7])
        #expect(FakePapyrusWorldStateBridgePort().questKey(editorID: "MQ101") == nil)
    }

    @Test func sessionMountsGraphsAndItemsAnswerForTheObjectBehindThem() {
        let session = FakeGameSessionPort()
        #expect(session.playerGraph == nil)
        #expect(session.playerAnimation == nil)

        let mounts = FakeMountPort()
        mounts.allowRiddenHorseSprint(true)
        let drive = FakePlayerMountDrivePort()
        mounts.drive = drive
        mounts.allowRiddenHorseSprint(true)
        #expect(drive.bridge.isSprintAllowed)

        let graphs = FakeActorGraphPort()
        let world = FakeActorGraphWorldPort()
        world.graphs = graphs
        #expect(world.graphInstance(of: .player) == nil)
        #expect(graphs.instanceCalls == [.player])

        #expect(FakeInventoryPort().itemDefinitions == nil)
    }
}
