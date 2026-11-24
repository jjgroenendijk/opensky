// The effects world forwards a blast's sight line, objects, object damage, and placed
// object, and a body's destruction damage; runes show their projectile's look.

import Foundation
@testable import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import OpenSkySessionTesting
import simd
import Testing

@MainActor
struct EffectsDestructionWitnessTests {
    private let host = CombatHost()
    private let adapter: EffectsWorldAdapter
    private let bridge = FakePapyrusWorldStateBridgePort()

    private static let barrel = ReferenceKey.plugin(name: "base.esm", objectID: 0x50)
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    init() {
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
        host.fakeEffects.recordsValue = EffectRecordStore(plugins: [])
        host.fakeScripts.bridge = bridge
        adapter = EffectsWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func aWallOnTheLineGivesItsDistance() {
        host.fakeCombat.sweepProjectileResult = ShapeSweepHit(
            reference: FormID(0x60), distance: 30, position: .zero, normal: SIMD3(-1, 0, 0),
            startsOverlapping: false, material: nil
        )
        #expect(adapter.explosionObstruction(from: .zero, to: SIMD3(100, 0, 0)) == 30)
        #expect(adapter.explosionObstruction(from: .zero, to: SIMD3(0.5, 0, 0)) == nil)
    }

    @Test func objectDamageGoesToTheScriptBridge() {
        bridge.damageDestructibleResult = true
        #expect(adapter.applyDestructionDamage(5, to: Self.barrel))
        #expect(adapter.applyPhysicsDestruction(6, to: Self.barrel))
        #expect(bridge.damageDestructibleCalls.count == 2)
        #expect(adapter.explosionObjects(within: 100, of: .zero).isEmpty)
        #expect(adapter.explosionObjects(within: 0, of: .zero).isEmpty)
        #expect(adapter.impulseDestructibles(within: 100, of: .zero).isEmpty)
    }

    @Test func anUnknownPlacedObjectIsNotMade() {
        let placement = ExplosionObjectPlacement(base: Self.barrel, position: .zero)
        #expect(!adapter.placeExplosionObject(placement))
    }

    @Test func aBlastOnAnActorWithoutASpecDoesNothing() {
        adapter.detonateEffectExplosion(Self.barrel, onActor: Self.actor, from: .player)
        #expect(host.fakeCombat.explosions.detonateCalls.isEmpty)
    }

    @Test func aBlastOnAnActorGoesOffAboveItsFeet() {
        let fake = host.fakeCombat.explosions
        fake.specForResult = ExplosionSpec(name: "Blast", damage: 10, radius: 100)
        fake.detonateResult = ExplosionReport(
            name: "Blast", cause: .spell, position: .zero, damaged: [:], soundsPlayed: 0,
            imageSpaceStrength: nil, hazardPlaced: false, debrisThrown: 0
        )
        host.fakeCombat.projectileTargetsResult = [MeleeTarget(
            key: Self.actor,
            feet: SIMD3(1, 2, 3)
        )]
        adapter.detonateEffectExplosion(Self.barrel, onActor: Self.actor, from: .player)
        #expect(fake.detonateCalls.first?.origin.shooter == .player)
    }

    @Test func aRuneWithoutItemDataShowsNothing() {
        host.fakeMagic.runeMarkers = [
            RuneMarker(position: SIMD3(1, 2, 3), projectile: FormID(0x70), isLit: true)
        ]
        #expect(adapter.frameLooks.extraModels().isEmpty)
        #expect(adapter.projectileAndFlashLights().isEmpty)
    }
}
