// What the package coordinator reads from the runtime, a running procedure, and the
// world: combat, situations, the running place, and the sandbox area. Synthetic records.

@testable import OpenSkyAIPackages
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyWorldConditions
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct PackageCoordinatorReadsTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)
    private static let clock = GameClock(hour: 9)
    private static let combatList = FormID(0x701)

    private func runtime() throws -> ActorPackageRuntime {
        let packages = try [
            PackageRuntimeFixture.package(id: 0x101, editorID: "Own"),
            PackageRuntimeFixture.package(id: 0x103, editorID: "CombatOverride")
        ]
        let fields = PackageRuntimeFixture.formIDField("ECOR", Self.combatList.rawValue)
        let base = try PackageRuntimeFixture.actorBase(
            id: 0x600, packages: [0x101], extraFields: fields
        )
        let store = PackageStore(
            packages: packages,
            actorTemplates: ActorTemplateResolver(actors: [0x600: base], leveledActors: [:]),
            formLists: [Self.combatList: [FormID(0x103)]]
        )
        var runtime = ActorPackageRuntime(store: store, conditionFunctions: .standard)
        try runtime.register(actor: Self.actor, base: base.formID)
        runtime.advance(clock: Self.clock) { _ in ConditionContext() }
        return runtime
    }

    @Test func aCombatSituationMakesTheActorIgnoreCombatPackages() throws {
        var runtime = try runtime()
        #expect(!runtime.ignoresCombat(Self.actor))
        runtime.setSituations(
            ([Self.actor], [Self.actor: .combat]),
            execution: { _ in nil }, clock: Self.clock, context: { ConditionContext() }
        )
        #expect(runtime.currentPackage(for: Self.actor)?.package.formID == FormID(0x103))
        #expect(runtime.ignoresCombat(Self.actor))
    }

    @Test func anExecutionThatRunsNothingHasNoPlaceSeatOrLeader() throws {
        let package = try #require(try runtime().currentPackage(for: Self.actor))
        let execution = PackageOverrideExecution(package: package)
        #expect(!execution.isWarning)
        #expect(execution.runningPlace == nil)
        #expect(execution.sandboxMachine == nil)
        #expect(execution.seat(of: 0) == nil)
        #expect(!execution.follows(.player))
        #expect(FakePackageWorld().firstLocation(of: package, actor: Self.actor) == nil)
    }

    @Test func aSandboxSearchesItsOwnCylinder() {
        var setup = PackageProcedureSetup(kind: .sandbox, center: .zero, radius: 500)
        setup.sandbox = PackageSandboxSetup(settings: .vanilla, start: .zero)
        let machine = PackageProcedureMachine(setup: setup)
        #expect(!machine.follows)
        let area = machine.idleArea(defaults: .vanilla)
        #expect(area.radius == 500)
        #expect(area.allowsMarkers)
        let follow = PackageProcedureMachine(
            setup: PackageProcedureSetup(kind: .follow, center: .zero, radius: 100)
        )
        #expect(follow.follows)
    }
}
