// The default list, the situation override lists, and the script package rank around the
// actor's own stack. Synthetic records only.

import Foundation
@testable import OpenSkyAIPackages
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import Testing

@MainActor
struct PackageListTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)
    private static let clock = GameClock(hour: 9)
    private static let defaultList = FormID(0x700)
    private static let combatList = FormID(0x701)

    /// Own package 0x101 runs only before 6:00, so at 9:00 the default list decides.
    private func runtime(ownValid: Bool = true) throws -> ActorPackageRuntime {
        let own = try PackageRuntimeFixture.package(
            id: 0x101, editorID: "Own",
            schedule: ownValid ? .anytime : Package.Schedule(
                month: -1, dayOfWeek: -1, date: 0, hour: 1, minute: 0, durationMinutes: 60
            )
        )
        let packages = try [
            own,
            PackageRuntimeFixture.package(id: 0x102, editorID: "Default"),
            PackageRuntimeFixture.package(id: 0x103, editorID: "CombatOverride"),
            PackageRuntimeFixture.package(id: 0x104, editorID: "Script"),
            PackageRuntimeFixture.package(id: 0x105, editorID: "Lasting", flags: .mustComplete)
        ]
        let fields = PackageRuntimeFixture.formIDField("DPLT", Self.defaultList.rawValue)
            + PackageRuntimeFixture.formIDField("ECOR", Self.combatList.rawValue)
        let base = try PackageRuntimeFixture.actorBase(
            id: 0x600, packages: [0x101], extraFields: fields
        )
        let store = PackageStore(
            packages: packages,
            actorTemplates: ActorTemplateResolver(actors: [0x600: base], leveledActors: [:]),
            formLists: [Self.defaultList: [FormID(0x102)], Self.combatList: [FormID(0x103)]]
        )
        var runtime = ActorPackageRuntime(store: store)
        try runtime.register(actor: Self.actor, base: base.formID)
        runtime.advance(clock: Self.clock) { _ in ConditionContext() }
        return runtime
    }

    private func current(_ runtime: ActorPackageRuntime) -> FormID? {
        runtime.currentPackage(for: Self.actor)?.package.formID
    }

    @Test func anActorWithNoValidOwnPackageFollowsItsDefaultList() throws {
        let runtime = try runtime(ownValid: false)
        #expect(current(runtime) == FormID(0x102))
        #expect(runtime.source(for: Self.actor) == .defaults)
    }

    @Test func theOwnStackRanksAboveTheDefaultList() throws {
        let runtime = try runtime()
        #expect(current(runtime) == FormID(0x101))
        #expect(runtime.source(for: Self.actor) == .own)
    }

    @Test func aCombatSituationRunsTheCombatOverrideList() throws {
        var runtime = try runtime()
        runtime.setSituation(.combat, actor: Self.actor, clock: Self.clock) { ConditionContext() }
        #expect(current(runtime) == FormID(0x103))
        #expect(runtime.source(for: Self.actor) == .situation(.combat))
        runtime.setSituation(nil, actor: Self.actor, clock: Self.clock) { ConditionContext() }
        #expect(current(runtime) == FormID(0x101))
    }

    @Test func aSituationWithoutAListKeepsTheOwnPackage() throws {
        var runtime = try runtime()
        runtime.setSituation(.spectator, actor: Self.actor, clock: Self.clock) {
            ConditionContext()
        }
        #expect(current(runtime) == FormID(0x101))
        #expect(runtime.situation(for: Self.actor) == .spectator)
    }

    @Test func aScriptPackageOutranksAllUntilTheNextEvaluation() throws {
        var runtime = try runtime()
        runtime.setSituation(.combat, actor: Self.actor, clock: Self.clock) { ConditionContext() }
        let accepted = runtime.setScriptPackage(
            FormID(0x104), actor: Self.actor, clock: Self.clock, context: ConditionContext()
        )
        #expect(accepted)
        #expect(current(runtime) == FormID(0x104))
        #expect(runtime.source(for: Self.actor) == .script)
        runtime.forceReevaluate(actor: Self.actor, clock: Self.clock, context: ConditionContext())
        #expect(current(runtime) == FormID(0x103))
        #expect(runtime.scriptPackage(for: Self.actor) == nil)
    }

    @Test func aMustCompleteScriptPackageStaysUntilItEnds() throws {
        var runtime = try runtime()
        runtime.setScriptPackage(
            FormID(0x105), actor: Self.actor, clock: Self.clock, context: ConditionContext()
        )
        runtime.forceReevaluate(actor: Self.actor, clock: Self.clock, context: ConditionContext())
        #expect(current(runtime) == FormID(0x105))
        runtime.packageEnded(actor: Self.actor, clock: Self.clock, context: ConditionContext())
        #expect(current(runtime) == FormID(0x101))
    }

    @Test func anUnknownScriptPackageIsRefused() throws {
        var runtime = try runtime()
        let accepted = runtime.setScriptPackage(
            FormID(0x999), actor: Self.actor, clock: Self.clock, context: ConditionContext()
        )
        #expect(!accepted)
        #expect(current(runtime) == FormID(0x101))
    }

    @Test func aPackageIsFoundByEditorIDOrFormID() throws {
        let store = try PackageStore(
            packages: [PackageRuntimeFixture.package(id: 0x104, editorID: "MQScript")],
            actorTemplates: ActorTemplateResolver(actors: [:], leveledActors: [:])
        )
        #expect(store.packageID(named: "mqscript") == FormID(0x104))
        #expect(store.packageID(named: "0x104") == FormID(0x104))
        #expect(store.packageID(named: "Missing") == nil)
    }
}
