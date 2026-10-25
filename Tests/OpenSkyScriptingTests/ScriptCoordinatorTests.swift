// The Scripts readout over a fake world: crosshair targeting, pause and step,
// and the no-VM readout. Every fixture is built in code.

@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ScriptCoordinatorTests {
    private let world = FakeScriptWorld()

    @Test func withoutAVMThePanelReadsEmpty() {
        let coordinator = ScriptCoordinator(world: world)
        #expect(coordinator.scriptsSnapshot == .empty)
        coordinator.setScriptsPaused(true)
        coordinator.stepScripts(ticks: 3)
    }

    @Test func crosshairTargetsTheResidentReference() throws {
        let (coordinator, _) = try whole()
        world.crosshairReference = FormID(1)
        world.residentKeys = [FormID(1): Self.key(1)]
        let snapshot = coordinator.scriptsSnapshot
        #expect(snapshot.targetDescription == Self.key(1).description)
        #expect(snapshot.targetScripts == ["ascript"])
    }

    /// An unresolved FormID still shows as itself.
    @Test func unresolvedCrosshairShowsTheBareFormID() throws {
        let (coordinator, _) = try whole()
        world.crosshairReference = FormID(9)
        let snapshot = coordinator.scriptsSnapshot
        #expect(snapshot.targetDescription == FormID(9).description)
        #expect(snapshot.targetScripts.isEmpty)
    }

    @Test func noCrosshairNamesNoTarget() throws {
        let (coordinator, _) = try whole()
        #expect(coordinator.scriptsSnapshot.targetDescription == nil)
        #expect(coordinator.scriptsSnapshot.instanceCount == 2)
    }

    @Test func pauseFreezesOnlyTheVMAndStepsStillRun() throws {
        let (coordinator, runtime) = try whole()
        coordinator.setScriptsPaused(true)
        #expect(runtime.isPaused)
        #expect(coordinator.scriptsSnapshot.isPaused)
        coordinator.stepScripts(ticks: 2)
        #expect(runtime.scheduler.tickCount == 2)
    }

    @Test func pausedAdvanceRunsNothing() throws {
        let (coordinator, runtime) = try whole()
        coordinator.setScriptsPaused(true)
        coordinator.advance(delta: 1)
        #expect(runtime.scheduler.tickCount == 0)
    }

    /// The VM's registry owns the bridge, so the initializer closes the loop with a
    /// weak link from the bridge back to the VM.
    @Test func theInitializerLinksTheBridgeToTheVM() throws {
        let runtime = try PapyrusWorldFixture.twoInstanceWorld(probe: PapyrusWorldProbeDispatch())
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        let coordinator = ScriptCoordinator(world: world, runtime: runtime, bridge: bridge)
        #expect(bridge.world === runtime)
        #expect(coordinator.bridge === bridge)
    }

    private func whole() throws -> (ScriptCoordinator, PapyrusWorldRuntime) {
        let runtime = try PapyrusWorldFixture.twoInstanceWorld(probe: PapyrusWorldProbeDispatch())
        return (ScriptCoordinator(world: world, runtime: runtime, bridge: nil), runtime)
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }
}

private final class FakeScriptWorld: ScriptWorld {
    var crosshairReference: FormID?
    var residentKeys: [FormID: ReferenceKey] = [:]
    var gameClock: GameClock?
    var playerLocation: ResolvedFormID??

    func referenceKey(formID: FormID) -> ReferenceKey? {
        residentKeys[formID]
    }
}
