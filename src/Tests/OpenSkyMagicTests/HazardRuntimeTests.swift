// The hazard runtime over synthetic specs: radius, target interval, lifetime,
// the player-only flag, the spawn limit, and cell unload.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import Testing

struct HazardRuntimeTests {
    static let fire = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)
    static let npc = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x700)
    static let cell = CellSceneLocation.interior(FormID(0x900))

    static func spec(
        radius: Float = 100,
        lifetime: Float = 0,
        interval: Float = 1,
        limit: UInt32 = 0,
        playerOnly: Bool = false
    ) -> HazardSpec {
        HazardSpec(
            hazard: fire,
            name: "FireHazard",
            spell: .plugin(name: "skyrim.esm", objectID: 0x600),
            radius: radius,
            lifetime: lifetime,
            targetInterval: interval,
            limit: limit,
            affectsPlayerOnly: playerOnly
        )
    }

    static func id(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: objectID)
    }

    static func actor(_ key: ReferenceKey, x: Float) -> MeleeTarget {
        MeleeTarget(key: key, feet: SIMD3(x, 0, 0))
    }

    @Test func anActorInsideIsHitOnEntryAndThenPerInterval() {
        var runtime = HazardRuntime()
        runtime.place(Self.spec(), id: Self.id(1), at: .zero, source: .placed(Self.cell))
        let inside = [Self.actor(.player, x: 50)]
        #expect(runtime.step(0.1, candidates: inside).first?.targets.map(\.key) == [.player])
        #expect(runtime.step(0.5, candidates: inside).isEmpty)
        #expect(runtime.step(0.5, candidates: inside).first?.targets.map(\.key) == [.player])
    }

    @Test func onlyAStepThatHitsCountsAsATick() {
        var runtime = HazardRuntime()
        runtime.place(Self.spec(), id: Self.id(1), at: .zero, source: .spawned)
        let inside = [Self.actor(.player, x: 50)]
        _ = runtime.step(0.1, candidates: inside)
        _ = runtime.step(0.5, candidates: inside)
        _ = runtime.step(0.5, candidates: inside)
        #expect(runtime.active[Self.id(1)]?.tickCount == 2)
    }

    @Test func anActorOutsideTheRadiusIsNotHit() {
        var runtime = HazardRuntime()
        runtime.place(Self.spec(radius: 30), id: Self.id(1), at: .zero, source: .placed(Self.cell))
        #expect(runtime.step(0.1, candidates: [Self.actor(Self.npc, x: 200)]).isEmpty)
    }

    @Test func leavingAndReturningHitsAgainAtOnce() {
        var runtime = HazardRuntime()
        runtime.place(Self.spec(interval: 5), id: Self.id(1), at: .zero, source: .placed(Self.cell))
        _ = runtime.step(0.1, candidates: [Self.actor(.player, x: 10)])
        _ = runtime.step(0.1, candidates: [])
        #expect(!runtime.step(0.1, candidates: [Self.actor(.player, x: 10)]).isEmpty)
    }

    @Test func playerOnlyHazardsSkipOtherActors() {
        var runtime = HazardRuntime()
        runtime.place(
            Self.spec(playerOnly: true), id: Self.id(1), at: .zero, source: .placed(Self.cell)
        )
        let hits = runtime.step(0.1, candidates: [
            Self.actor(Self.npc, x: 5), Self.actor(.player, x: 20)
        ])
        #expect(hits.first?.targets.map(\.key) == [.player])
    }

    @Test func aSpawnedHazardExpiresAtItsLifetime() {
        var runtime = HazardRuntime()
        runtime.place(Self.spec(lifetime: 2), id: Self.id(1), at: .zero, source: .spawned)
        _ = runtime.step(1.5, candidates: [])
        #expect(runtime.active[Self.id(1)]?.remainingLifetime == 0.5)
        _ = runtime.step(0.6, candidates: [])
        #expect(runtime.active.isEmpty)
    }

    @Test func aPlacedHazardIgnoresItsLifetime() {
        var runtime = HazardRuntime()
        runtime.place(Self.spec(lifetime: 1), id: Self.id(1), at: .zero, source: .placed(Self.cell))
        _ = runtime.step(5, candidates: [])
        #expect(runtime.active.count == 1)
    }

    @Test func theLimitDropsTheOldestSpawn() {
        var runtime = HazardRuntime()
        for objectID in UInt32(1) ... 3 {
            runtime.place(Self.spec(limit: 2), id: Self.id(objectID), at: .zero, source: .spawned)
        }
        #expect(Set(runtime.active.keys) == [Self.id(2), Self.id(3)])
    }

    @Test func unloadingACellDropsOnlyItsHazards() {
        var runtime = HazardRuntime()
        runtime.place(Self.spec(), id: Self.id(1), at: .zero, source: .placed(Self.cell))
        runtime.place(Self.spec(), id: Self.id(2), at: .zero, source: .spawned)
        runtime.removeAll(placedIn: Self.cell)
        #expect(Array(runtime.active.keys) == [Self.id(2)])
    }

    @Test func aZeroIntervalIsRaisedToTheMinimum() {
        #expect(Self.spec(interval: 0).targetInterval == HazardSpec.minimumInterval)
    }
}

@MainActor
struct HazardRowTests {
    @Test func rowsShowLifetimeAndTheLastHit() {
        let coordinator = HazardCoordinator()
        coordinator.spawn(HazardPlacement(
            id: HazardRuntimeTests.id(1), spec: HazardRuntimeTests.spec(lifetime: 3),
            position: .zero
        ))
        #expect(coordinator.hazardRows == [TrapHazardRow(
            name: "FireHazard", remainingLifetime: 3, lastHitTargets: 0, lastHitEffects: 0
        )])
        #expect(TrapReadout.line(coordinator.hazardRows[0]) == "FireHazard: 3.0 s left, no hit yet")
    }
}
