// The effects world shows explosions, lights, and health cues, and places effects on actors.

import Foundation
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkySessionTesting
import simd
import Testing

@MainActor
struct EffectsBlastsTests {
    private let host = CombatHost()
    private let adapter: EffectsWorldAdapter

    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let light = ReferenceKey.plugin(name: "base.esm", objectID: 0x40)

    init() {
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        host.fakeEffects.recordsValue = EffectRecordStore(plugins: [])
        adapter = EffectsWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func explosionsReachTheHazardsAndCombat() {
        host.fakeHazardWorld.hazardCandidatesResult = [MeleeTarget(key: Self.actor, feet: .zero)]
        host.fakeCombat.applyHealthDamageResult = true
        #expect(adapter.explosionTargets().map(\.key) == [Self.actor])
        #expect(adapter.explosionViewer() == nil)
        #expect(adapter.applyExplosionDamage(10, to: Self.actor))
        #expect(!adapter.placeExplosionHazard(Self.light, at: .zero))
        adapter.playExplosionSound(Self.light, at: .zero)
        adapter.startExplosionImageSpace(Self.light, strength: 1)
    }

    @Test func modelsAndLightsGoToTheEffects() {
        adapter.showExplosionModel("Effects/Blast.nif", at: SIMD3(1, 2, 3))
        adapter.showExplosionLight(Self.light, at: .zero)
        adapter.showMuzzleFlash(ProjectileVisuals(), at: .zero, along: SIMD3(1, 0, 0))
        #expect(host.fakeEffects.showModelCalls.count == 1)
        #expect(host.fakeEffects.addFlashLightCalls.count == 1)
        #expect(host.fakeEffects.showMuzzleFlashCalls.count == 1)
    }

    @Test func anUnknownLightRendersNothing() {
        #expect(adapter.renderLight(Self.light, at: .zero, strength: 1) == nil)
        #expect(adapter.projectileAndFlashLights().isEmpty)
        #expect(adapter.blasts.projectileModels().isEmpty)
        adapter.playExplosionImpact(Self.light, at: .zero)
    }

    @Test func effectsPlaceOnActorsFromTheirObservation() {
        host.fakeActorWorld.combatActorResult = CombatActorObservation(
            key: Self.actor, feet: SIMD3(1, 2, 3)
        )
        let transform = adapter.effectTransform(of: Self.actor)
        #expect(transform?.columns.3 == SIMD4(1, 2, 3, 1))
        #expect(adapter.effectTransform(of: .player) == nil)
        #expect(adapter.effectBones(of: Self.actor).isEmpty)
        #expect(adapter.effectCamera == nil)
        #expect(adapter.membraneTarget(of: .player) == .player)
        #expect(adapter.membraneTarget(of: Self.actor) == .actor(0x20))
    }

    @Test func healthCuesResetTheEffects() {
        adapter.resetHealthCues()
        adapter.fadeOutHealthCues()
        #expect(host.fakeEffects.resetHealthCuesCallCount == 2)
        adapter.detonateEffectExplosion(Self.light, at: .zero)
    }
}
