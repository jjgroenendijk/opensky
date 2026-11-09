// The effects world pushes bodies and actors, and reads water and health, through its ports.

import Foundation
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct EffectsBodyImpulsesTests {
    private let host = CombatHost()
    private let adapter: EffectsWorldAdapter

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let dead = ReferenceKey.plugin(name: "base.esm", objectID: 0x21)

    init() {
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        adapter = EffectsWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func anEmptyBodyWorldHasNoImpulseBodies() {
        #expect(adapter.impulseBodies().isEmpty)
    }

    @Test func impulseActorsAreThePlayerAndLivingActors() {
        host.fakeHazardWorld.hazardCandidatesResult = [
            MeleeTarget(key: .player, feet: .zero),
            MeleeTarget(key: Self.actor, feet: .zero),
            MeleeTarget(key: Self.dead, feet: .zero)
        ]
        host.fakeActorWorld.combatActorResult = CombatActorObservation(key: Self.actor, feet: .zero)
        #expect(adapter.impulseActors().map(\.key) == [.player, Self.actor, Self.dead])
    }

    @Test func waterReadsComeFromTheStreamer() {
        host.fakeStreamer.sampleWaterHeightResult = 12
        #expect(adapter.waterHeight(at: SIMD2(1, 2)) == 12)
        #expect(adapter.waterCurrent(at: .zero) == nil)
        #expect(!adapter.isDangerousWater(at: .zero))
        adapter.waterContacts([])
    }

    @Test func withoutRaceRecordsAnActorIsAPushableMediumBody() {
        #expect(adapter.race(of: Self.actor) == nil)
        #expect(adapter.raceSize(of: Self.actor) == 1)
        #expect(adapter.isPushable(Self.actor))
        _ = adapter.waterPushRace(of: Self.actor)
    }

    @Test func healthAndDamageGoThroughCombat() {
        host.fakeCombatWorld.healthResult = (current: 40, maximum: 100)
        host.fakeCombat.applyHealthDamageResult = true
        #expect(adapter.actorHealth(of: Self.actor)?.current == 40)
        #expect(adapter.applyPhysicsDamage(5, to: Self.actor))
        #expect(host.fakeCombat.applyHealthDamageCalls.count == 1)
    }

    @Test func aKnockDownUsesTheRagdollFirst() {
        #expect(!adapter.knockDown(Self.actor, from: .zero, magnitude: 0))
        host.fakeRagdoll.knockDownResult = true
        #expect(adapter.knockDown(Self.actor, from: .zero, magnitude: 2))
        host.fakeRagdoll.knockDownResult = false
        #expect(!adapter.knockDown(Self.actor, from: .zero, magnitude: 2))
    }

    @Test func aKnockMovesAnNPCThroughTheStreamer() {
        #expect(!adapter.knockActor(Self.actor, velocity: .zero, knockdown: false))
        host.fakeStreamer.knockActorResult = true
        #expect(adapter.knockActor(Self.actor, velocity: SIMD3(1, 0, 0), knockdown: true))
        #expect(adapter.knockActor(.player, velocity: SIMD3(1, 0, 0), knockdown: false))
        #expect(host.fakeStreamer.knockActorCalls.map(\.actor) == [Self.actor])
    }
}
