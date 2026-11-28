// An NPC's bash: the bash pool pick, the Bash line, the bash reach, and the bash damage.
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

    /// A styled opponent with a sword, whose bash value makes its offensive bash certain.
    @Test func aStyledOpponentBashesThePlayerAndSaysTheBashLine() {
        let (runtime, world) = CombatLoopFixture.session()
        world.weapons[Self.opponent] = MeleeWeaponProfile(
            damage: 12, reach: 1, handType: .sword
        )
        var style = CombatStyleTuning.neutral
        style.offensiveMultiplier = 0
        style.bash.bash = 1000
        world.styles[Self.opponent] = style
        var data = Self.attack(.bash).data
        data.strikeAngle = 180
        world.raceAttacks[Self.opponent] = [RaceAttack(properties: data, event: "bashStart")]
        CombatLoopFixture.engage(runtime, world)
        var elapsed: Float = 0
        while world.damage[.player] == nil, elapsed < 5 {
            CombatLoopFixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)
            elapsed += CombatLoopRuntime.fixedStepSeconds
        }
        #expect(world.bashLines.first == [Self.opponent, .player])
        #expect(world.clips.contains { $0.clip == .bash && $0.key == Self.opponent })
        #expect(runtime.pickedAttacks[Self.opponent]?.event == "bashStart")
        #expect((runtime.behaviors[Self.opponent]?.bashCount ?? 0) >= 1)
        #expect(world.damage[.player] != nil)
    }

    @Test func aBashWithNoPickGoesBackToTheLoop() {
        let (runtime, world) = CombatLoopFixture.session()
        world.weapons[Self.opponent] = MeleeWeaponProfile(
            damage: 12, reach: 1, handType: .sword
        )
        var style = CombatStyleTuning.neutral
        style.offensiveMultiplier = 0
        style.bash.bash = 1000
        world.styles[Self.opponent] = style
        var data = Self.attack(.bash).data
        data.recoveryTime = 1000
        world.raceAttacks[Self.opponent] = [RaceAttack(properties: data, event: "bashStart")]
        runtime.attackUses[Self.opponent] = ["bashstart": 0]
        CombatLoopFixture.engage(runtime, world)
        CombatLoopFixture.run(runtime, seconds: 1)
        #expect(world.bashLines.isEmpty)
        #expect(runtime.behaviors[Self.opponent]?.bashCount == 0)
        #expect(runtime.behaviors[Self.opponent]?.isBashing == false)
    }
}
