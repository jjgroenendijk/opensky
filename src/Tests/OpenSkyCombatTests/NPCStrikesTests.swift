// The hand order of an NPC with a weapon in each hand.

import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import Testing

struct NPCStrikesTests {
    @Test func twoWeaponsStrikeRightThenLeftThenBoth() {
        var strikes = NPCStrikes()
        var hands: [MeleeStrikeHand] = []
        for _ in 0 ..< 4 {
            strikes.start(dual: true)
            hands.append(strikes.hand)
        }
        #expect(hands == [.right, .left, .dual, .right])
    }

    @Test func oneWeaponAlwaysStrikesRight() {
        var strikes = NPCStrikes()
        strikes.start(dual: false)
        strikes.start(dual: false)
        #expect(strikes.hand == .right)
        let sword = MeleeWeaponProfile(damage: 5, reach: 1, handType: .sword)
        #expect(strikes.weapon(right: sword, left: nil) == sword)
        #expect(MeleeStrikeHand.dual.weapons(right: sword, left: nil) == [sword])
    }
}
