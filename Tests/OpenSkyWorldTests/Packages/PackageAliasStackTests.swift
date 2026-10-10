// Alias packages run ahead of the actor's own, a patrol walks its whole path, and a
// held package reports which quest its locations name. Synthetic records only.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct PackageAliasStackTests {
    private static let actorKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)
    private static let quest = FormID(0x900)

    private func runtime() throws -> ActorPackageRuntime {
        let own = try PackageRuntimeFixture.package(id: 0x101, editorID: "Own")
        let alias = try PackageRuntimeFixture.package(id: 0x102, editorID: "Alias")
        let actor = try PackageRuntimeFixture.actorBase(id: 0x600, packages: [0x101])
        let store = PackageStore(
            packages: [own, alias],
            actorTemplates: ActorTemplateResolver(actors: [0x600: actor], leveledActors: [:])
        )
        var runtime = ActorPackageRuntime(store: store)
        try runtime.register(actor: Self.actorKey, base: actor.formID)
        runtime.advance(clock: GameClock(hour: 9)) { _ in ConditionContext() }
        return runtime
    }

    @Test func anAliasPackageRunsAheadOfTheActorsOwn() throws {
        var runtime = try runtime()
        #expect(runtime.currentPackage(for: Self.actorKey)?.package.formID == FormID(0x101))
        #expect(runtime.hold(for: Self.actorKey) == nil)

        let stack = PackageAliasStack(packages: [FormID(0x102)], quest: Self.quest)
        runtime.setAliasStack(stack, actor: Self.actorKey, clock: GameClock(hour: 9)) {
            ConditionContext()
        }
        #expect(runtime.currentPackage(for: Self.actorKey)?.package.formID == FormID(0x102))
        #expect(runtime.hold(for: Self.actorKey) == PackageHold(aliasQuest: Self.quest))

        runtime.setAliasStack(nil, actor: Self.actorKey, clock: GameClock(hour: 9)) {
            ConditionContext()
        }
        #expect(runtime.currentPackage(for: Self.actorKey)?.package.formID == FormID(0x101))
    }

    @Test func aPatrolWalksEveryPointThenFinishes() {
        let points: [SIMD3<Float>] = [[1, 0, 0], [2, 0, 0], [3, 0, 0]]
        var patrol = PackageProcedureMachine(
            kind: .patrol, center: .zero, destination: points[0], radius: 0,
            path: Array(points.dropFirst()), seed: 1
        )
        #expect(patrol.start() == [.move(to: points[0])])
        #expect(patrol.handle(.arrived) == [.move(to: points[1])])
        #expect(patrol.handle(.arrived) == [.move(to: points[2])])
        #expect(patrol.handle(.arrived).isEmpty)
        #expect(patrol.state == .complete)
    }
}
