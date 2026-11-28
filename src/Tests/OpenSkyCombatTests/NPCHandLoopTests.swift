// Each hand's attack loop: a styled NPC with a weapon in each hand rolls per hand, a
// left-hand roll swings the left hand, and a dual-wield pick swings both.
// Rules: docs/engine/combat-blocking.md ("Loops that run together").

import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
import Testing

@MainActor
struct NPCHandLoopTests {
    private static let opponent = CombatLoopFixture.opponent

    private static func attack(_ event: String, _ flags: RaceAttack.Flags = []) -> RaceAttack {
        var data = RaceAttack.Properties()
        data.flags = flags
        data.attackChance = 1
        data.strikeAngle = 180
        return RaceAttack(properties: data, event: event)
    }

    @Test func eachHandRollsAndTheFirstToPassAttacks() {
        var settings = CombatBehaviorFixture.neverCasting.tuned(by: .neutral)
        settings.blockLoop = nil
        settings.closeRange = nil
        settings.attackChance = 0.4
        var machine = CombatBehaviorFixture.machine(settings: settings)
        var inputs = CombatBehaviorFixture.inputs()
        inputs.holdsTwoWeapons = true
        inputs.weaponOut = true
        var hands: [MeleeStrikeHand?] = []
        for step in CombatBehaviorFixture.run(&machine, seconds: 30, inputs: inputs)
            where step.startedAttack
        {
            hands.append(step.attackHand)
        }
        #expect(hands.contains(.right))
        #expect(hands.contains(.left))
        #expect(!hands.contains(nil))
        inputs.holdsTwoWeapons = false
        var single = CombatBehaviorFixture.machine(settings: settings)
        let steps = CombatBehaviorFixture.run(&single, seconds: 10, inputs: inputs)
        #expect(steps.filter(\.startedAttack).allSatisfy { $0.attackHand == nil })
    }

    @Test func aDualWieldAttackNeedsAWeaponInEachHand() {
        let entries = [Self.attack("attackStartDualWield"), Self.attack("attackStart")]
        var situation = NPCAttackSituation()
        #expect(NPCAttackPick.candidates(entries, situation: situation).map(\.attack.event)
            == ["attackStart"])
        situation.holdsTwoWeapons = true
        #expect(NPCAttackPick.candidates(entries, situation: situation).count == 2)
        var strikes = NPCStrikes()
        strikes.start(dual: true, hand: .left)
        #expect(strikes.hand == .left)
        strikes.swingBoth()
        #expect(strikes.hand == .dual)
        strikes.start(dual: false, hand: .left)
        #expect(strikes.hand == .right)
    }

    /// A styled dual-wielder whose only attacks are a left-hand one and a dual-wield one.
    @Test func aStyledDualWielderSwingsItsLeftHandAndBoth() {
        let (runtime, world) = CombatLoopFixture.session()
        let sword = MeleeWeaponProfile(damage: 12, reach: 1, handType: .sword)
        world.weapons[Self.opponent] = sword
        world.leftWeapons[Self.opponent] = sword
        world.styles[Self.opponent] = .neutral
        world.raceAttacks[Self.opponent] = [
            Self.attack("attackStartLeftHand", .leftHand), Self.attack("attackStartDualWield")
        ]
        CombatLoopFixture.engage(runtime, world)
        CombatLoopFixture.run(runtime, seconds: 20)
        #expect(world.clips.contains { $0.clip == .leftAttack })
        let events = Set(runtime.attackUses[Self.opponent, default: [:]].keys)
        #expect(events.contains("attackstartlefthand"))
        #expect(events.contains("attackstartdualwield"))
    }
}
