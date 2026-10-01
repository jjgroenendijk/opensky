// The Scripts panel over a fake world: crosshair targeting, pause and step,
// and the no-VM readout. Every fixture is built in code.

@testable import FormatsESMTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ScriptCoordinatorTests {
    private let world = FakeScriptWorld()
    private let coordinator = ScriptCoordinator()

    init() {
        coordinator.attach(world: world)
    }

    @Test func withoutAVMThePanelReadsEmpty() {
        #expect(coordinator.scriptsSnapshot == .empty)
        #expect(coordinator.questAliasQuestEditorIDs.isEmpty)
        #expect(coordinator.questAliasTable(editorID: "MQ101") == nil)
        coordinator.setScriptsPaused(true)
        coordinator.stepScripts(ticks: 3)
    }

    @Test func crosshairTargetsTheResidentReference() throws {
        try install()
        world.crosshairReference = FormID(1)
        world.residentKeys = [FormID(1): Self.key(1)]
        let snapshot = coordinator.scriptsSnapshot
        #expect(snapshot.targetDescription == Self.key(1).description)
        #expect(snapshot.targetScripts == ["ascript"])
    }

    /// An unresolved FormID still shows as itself.
    @Test func unresolvedCrosshairShowsTheBareFormID() throws {
        try install()
        world.crosshairReference = FormID(9)
        let snapshot = coordinator.scriptsSnapshot
        #expect(snapshot.targetDescription == FormID(9).description)
        #expect(snapshot.targetScripts.isEmpty)
    }

    @Test func noCrosshairNamesNoTarget() throws {
        try install()
        #expect(coordinator.scriptsSnapshot.targetDescription == nil)
        #expect(coordinator.scriptsSnapshot.instanceCount == 2)
    }

    @Test func pauseFreezesOnlyTheVMAndStepsStillRun() throws {
        let runtime = try install()
        coordinator.setScriptsPaused(true)
        #expect(runtime.isPaused)
        #expect(coordinator.scriptsSnapshot.isPaused)
        coordinator.stepScripts(ticks: 2)
        #expect(runtime.scheduler.tickCount == 2)
    }

    @Test func pausedAdvanceRunsNothing() throws {
        let runtime = try install()
        coordinator.setScriptsPaused(true)
        coordinator.advance(delta: 1)
        #expect(runtime.scheduler.tickCount == 0)
    }

    /// The VM's registry owns the bridge, so `install` closes the loop with a
    /// weak link from the bridge back to the VM.
    @Test func installLinksTheBridgeToTheVM() throws {
        let runtime = try PapyrusWorldFixture.twoInstanceWorld(probe: PapyrusWorldProbeDispatch())
        let bridge = PapyrusWorldStateBridge(worldState: WorldStateStore())
        coordinator.install(runtime: runtime, bridge: bridge)
        #expect(bridge.world === runtime)
        #expect(coordinator.bridge === bridge)
    }

    @discardableResult
    private func install() throws -> PapyrusWorldRuntime {
        let runtime = try PapyrusWorldFixture.twoInstanceWorld(probe: PapyrusWorldProbeDispatch())
        coordinator.install(runtime: runtime, bridge: nil)
        return runtime
    }

    private static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: PapyrusWorldFixture.pluginName, objectID: objectID)
    }
}

private final class FakeScriptWorld: ScriptWorld {
    var crosshairReference: FormID?
    var residentKeys: [FormID: ReferenceKey] = [:]
    var gameClock: GameClock?

    func referenceKey(formID: FormID) -> ReferenceKey? {
        residentKeys[formID]
    }
}
