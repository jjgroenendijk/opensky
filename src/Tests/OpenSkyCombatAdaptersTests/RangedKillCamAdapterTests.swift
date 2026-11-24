// The ranged kill cam reads its shot and target through the combat ports, the release
// check's damage reads the spell through magic, and objects need the script bridge.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
@testable import OpenSkyMagicInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct RangedKillCamAdapterTests {
    private let host = CombatHost()
    private static let foe = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    private var cinematic: CinematicCameraWorldAdapter {
        CinematicCameraWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func aShotThatLandedHasNoAnchor() {
        #expect(cinematic.cinematicProjectileAnchor(3) == nil)
    }

    @Test func aTargetNotInTheWorldCountsAsDead() {
        #expect(cinematic.cinematicTargetIsDead(Self.foe))
        host.fakeActorWorld.combatActorResult = CombatActorObservation(key: Self.foe, feet: .zero)
        #expect(!cinematic.cinematicTargetIsDead(Self.foe))
    }

    @Test func thePassedCheckStartsTheCamera() {
        CombatWorldAdapter(game: host).impactEffects.playRangedKillCam(
            projectile: 4,
            target: Self.foe
        )
        #expect(host.fakeCinematicCamera.playRangedKillCamCalls.map(\.id) == [4])
    }

    @Test func aSpellsDamageComesFromMagic() {
        host.fakeMagic.healthDamageResult = 25
        let spell = SpellPayload(
            spell: Self.foe, sourcePlugin: "base.esm", caster: .player, entries: [],
            isHostile: true, ignoresResistance: false, projectile: nil, name: "Firebolt"
        )
        #expect(CombatWorldAdapter(game: host).spellHealthDamage(spell) == 25)
    }

    @Test func aWorldWithoutAScriptBridgeHasNoObjectsToDamage() {
        let adapter = CombatWorldAdapter(game: host)
        #expect(adapter.destructibleObjects(within: 100, of: .zero).isEmpty)
        #expect(!adapter.damageDestructible(Self.foe, amount: 5))
        #expect(adapter.destructibleKey(reference: FormID(0x20)) == nil)
    }
}
