// An NPC's bash: the bash pool pick and the bash damage.
// Rules: docs/engine/combat-blocking.md ("Bash").

import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import OpenSkyConditions
@testable import OpenSkyFormatsESM
import Testing

@MainActor
struct NPCBashTests {
    private static let opponent = CombatLoopFixture.opponent

    private static func attack(_ flags: RaceAttack.Flags) -> NPCAttack {
        var data = RaceAttack.Properties()
        data.flags = flags
        data.attackChance = 1
        return NPCAttack(event: "bashStart", data: data)
    }

    @Test func aBashAttackMakesABashBlowThatDealsTheBashDamage() {
        let bash = CombatNPCBlowLanding.blow(
            by: Self.opponent, weapon: .unarmed, attack: Self.attack(.bash)
        )
        #expect(bash.kind == .bash)
        let power = CombatNPCBlowLanding.blow(
            by: Self.opponent, weapon: .unarmed, attack: Self.attack([.bash, .powerAttack])
        )
        #expect(power.kind == .powerBash)
        let world = FakeCombatWorld()
        let landing = CombatNPCBlowLanding(
            world: world, settings: .synthetic, skillUses: .vanilla, staggers: .vanilla
        )
        let sword = MeleeWeaponProfile(damage: 10, reach: 1, handType: .sword)
        let plain = landing.appliedDamage(by: Self.opponent, weapon: sword, on: .player)
        let bashed = landing.appliedDamage(
            by: Self.opponent, weapon: sword, on: .player, attack: Self.attack(.bash)
        )
        let source = BashSource(
            weaponDamage: 10, shieldRating: nil,
            blockSkill: world.combatBlockSkill(of: Self.opponent)
        )
        let expected = MeleeBash.damage(source, isPlayer: false, isPower: false, settings: .vanilla)
        #expect(abs(bashed / plain - expected / 10) < 0.001)
        world.shieldRatings[Self.opponent] = 30
        let shielded = landing.appliedDamage(
            by: Self.opponent, weapon: sword, on: .player, attack: Self.attack(.bash)
        )
        #expect(shielded > bashed)
    }

    @Test func theBashPoolTakesOnlyRightHandBashes() {
        let entries = [
            RaceAttack(properties: Self.attack(.bash).data, event: "bashStart"),
            RaceAttack(properties: Self.attack([.bash, .leftHand]).data, event: "bashLeft"),
            RaceAttack(properties: Self.attack([]).data, event: "attackStart")
        ]
        var situation = NPCAttackSituation()
        situation.pool = .bash
        let events = NPCAttackPick.candidates(entries, situation: situation).map(\.attack.event)
        #expect(events == ["bashStart"])
    }
}
