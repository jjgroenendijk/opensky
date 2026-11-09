// With records loaded, the adapters build their runtimes and read race flags.

import Foundation
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkySessionTesting
import Testing

@MainActor
struct CombatRecordsTests {
    private let host = CombatHost()
    private let records = FakeCombatRecords()

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let raceID: UInt32 = 0x200
    private static let clock = { Date(timeIntervalSince1970: 0) }

    init() throws {
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        host.combatRecords = records
        let race = try FakeCombatRecords.race(
            formID: Self.raceID, flags: [.flies, .noWeaponBlood, .noBloodDecal]
        )
        records.actorValueBaselines = FakeCombatRecords.baselines(
            race: race,
            pluginName: "base.esm"
        )
        records.effectRecords = EffectRecordStore(plugins: [])
        host.fakeEffects.recordsValue = EffectRecordStore(plugins: [])
        host.fakeMenuWorld.raceOfResult = FormID(Self.raceID)
    }

    @Test func recordsGiveTheCombatAndRagdollSessionData() {
        let combat = CombatWorldAdapter(game: host).sessionData()
        #expect(combat?.items == nil)
        #expect(combat?.impacts == nil)
        #expect(RagdollWorldAdapter(game: host).sessionData() != nil)
    }

    @Test func recordsGiveTheEffectsTheirRuntimes() {
        let effects = EffectsWorldAdapter(game: host, now: Self.clock)
        _ = effects.makeExplosions()
        _ = effects.bodyImpulses.makeImpulses(world: effects)
        effects.playCollision(BodyCollision(
            body: Self.actor, position: .zero, speedLoss: 1, material: FormID(0x10)
        ))
        #expect(host.fakeCombatWorld.playImpactImpactAtGainCalls.isEmpty)
    }

    @Test func theRaceRecordSaysTheActorFliesAndKeepsWeaponsClean() {
        let combat = CombatWorldAdapter(game: host)
        #expect(combat.actorFlies(Self.actor))
        #expect(combat.impactMaterial(of: Self.actor) == nil)
        combat.run([.drewBlood(
            CombatHitRecord(damage: 5, kind: .melee, attacker: .player), target: Self.actor
        )])
        #expect(host.fakeEffects.bloodyWeaponCalls.isEmpty)
    }

    @Test func aRaceWithNoBloodDecalShowsNoDefaultBlood() {
        RagdollWorldAdapter(game: host)
            .showDismemberment(of: Self.actor, node: "NPC Head", at: .zero)
        #expect(host.fakeEffects.showDefaultBloodCalls.isEmpty)
        #expect(host.fakeEffects.showDismemberParticleCalls.count == 1)
    }

    @Test func aMeleeImpactOnAnActorShowsOnThatActor() throws {
        let file = try ESMFixture.plugin(records: [
            ESMFixture.record("IPCT", formID: 0x300, data: ESMFixture.field(
                "EDID", ESMFixture.zstring("BladeImpact")
            ))
        ])
        let impact = try Impact(record: ESMFixture.firstRecord(type: "IPCT", in: file))
        let resolved = ResolvedMeleeImpact(sound: FormID(0x10), impact: impact, target: Self.actor)
        CombatWorldAdapter(game: host).run([.playImpact(resolved, at: SIMD3(1, 2, 3))])
        #expect(host.fakeEffects.showImpactCalls.count == 1)
    }

    @Test func theSessionInitialisersWorkWithoutAStage() {
        _ = CinematicCameraWorldAdapter(game: host, stage: nil, now: Self.clock)
        _ = EffectsWorldAdapter(game: host, stage: nil, now: Self.clock)
    }
}
