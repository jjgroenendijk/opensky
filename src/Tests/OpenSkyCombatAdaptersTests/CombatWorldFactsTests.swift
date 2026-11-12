// The combat world reads actors, factions, perks, and gear through its ports.

import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyPerceptionInterface
import OpenSkyProgressionInterface
import OpenSkySessionTesting
import OpenSkyWorldInterface
import Testing

@MainActor
struct CombatWorldFactsTests {
    private let host = CombatHost()
    private var adapter: CombatWorldAdapter {
        CombatWorldAdapter(game: host)
    }

    private static let foe = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)
    private static let foeSeen = CombatActorObservation(key: foe, feet: SIMD3(100, 0, 0))

    @Test func residentActorsComeFromTheActorWorld() {
        host.fakeActorWorld.combatActorsResult = [Self.foeSeen]
        host.fakeActorWorld.combatActorResult = Self.foeSeen
        #expect(adapter.residentActors().map(\.key) == [Self.foe])
        #expect(adapter.residentActor(key: Self.foe)?.key == Self.foe)
        #expect(host.fakeActorWorld.combatActorCalls == [Self.foe])
        #expect(adapter.selectedActor() == nil)
    }

    @Test func hostilityAndReactionGoThroughTheFactions() {
        host.fakeFactions.hostilityResult = .hostile
        host.fakeFactions.setHostilityResult = true
        #expect(adapter.hostility(of: Self.foe) == .hostile)
        #expect(adapter.setHostility(.neutral, on: Self.foe))
        #expect(host.fakeFactions.setHostilityCalls.map(\.key) == [Self.foe])
        #expect(adapter.reaction(of: Self.foe, toward: .player) == nil)
        #expect(host.fakeFactions.reactionCalls.map(\.observer) == [Self.foe])
    }

    @Test func withoutRuntimesTheActorFactsAreEmpty() {
        #expect(adapter.awareness(of: Self.foe, toward: .player).state == .unaware)
        #expect(adapter.actorValues(of: Self.foe) == nil)
        #expect(adapter.health(of: Self.foe) == nil)
        #expect(!adapter.damageHealth(by: 5, of: Self.foe))
        adapter.damageStamina(by: 5, of: Self.foe)
        adapter.pauseBowZoomStamina()
        #expect(adapter.level(of: Self.foe) == nil)
        #expect(!adapter.ownsPerk(editorID: "Juggernaut", on: .player))
        #expect(adapter.combatStyle(of: Self.foe) == nil)
        #expect(adapter.playerAttacker == nil)
        #expect(adapter.playerShooter == nil)
        #expect(!adapter.isInInterior)
    }

    @Test func perkValuesComeFromThePerkPort() {
        host.fakePerks.multiplierResult = 1.5
        #expect(adapter.perks.perkMultiplier(at: .modAttackDamage, on: .player) == 1.5)
        #expect(host.fakePerks.multiplierCalls.count == 1)
    }

    @Test func gearReadsTheMagicAndInventoryPorts() {
        host.fakeMagic.influenceResult = ActorMagicInfluence()
        host.fakeMagic.hasReadiedSpellResult = true
        _ = adapter.gearReads.magicInfluence(of: Self.foe)
        #expect(host.fakeMagic.influenceCalls == [Self.foe])
        #expect(adapter.gearReads.hasReadiedSpell(in: .left))
        #expect(adapter.gearReads.enchantmentProfile(of: FormID(0x500)) == nil)
        #expect(adapter.gearReads.equipment == nil)
        #expect(adapter.gearReads.temperLevel(of: FormID(0x500)) == 0)
        #expect(adapter.gearReads.equippedItems(of: .player).isEmpty)
        #expect(adapter.gearReads.playerCarriedItems().isEmpty)
        #expect(!adapter.gearReads.addItem(FormID(0x500), count: 1, to: Self.foe))
        #expect(!adapter.gearReads.removeOneFromPlayer(FormID(0x500)))
    }

    @Test func spellCastsNeedACasterRuntime() {
        #expect(adapter.castingFacts(of: Self.foe) == nil)
        #expect(!adapter.shout(Self.foe, by: Self.foe))
        #expect(!adapter.beginCast(Self.foe, by: Self.foe))
        #expect(!adapter.releaseCast(by: Self.foe))
        adapter.cancelCast(by: Self.foe)
    }
}
