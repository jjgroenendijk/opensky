// The stagger magnitude, block recoil, and chance from the `fStagger*` settings.
// Expected values use the install's values (docs/engine/melee-combat.md#stagger).

import OpenSkyCombatInterface
import Testing

struct StaggerRuleTests {
    private let settings = StaggerSettings.vanilla

    @Test func aSwingOnAnNPCKeepsTheWeaponStagger() {
        var hit = StaggerHit(weaponStagger: 0.75)
        hit.perkMultiplier = 2
        #expect(StaggerRule.magnitude(hit, settings: settings) == 1.5)
    }

    @Test func thePlayerStaggersLessByTheMassSetting() {
        var hit = StaggerHit(weaponStagger: 1)
        hit.isPlayerTarget = true
        let magnitude = StaggerRule.magnitude(hit, settings: settings)
        #expect(abs(magnitude - 2.1 / 3.6) < 0.0001)
    }

    @Test func aBlockedSwingLosesItsStaggerButAPowerAttackKeepsIt() {
        var hit = StaggerHit(weaponStagger: 1)
        hit.wasBlocked = true
        #expect(StaggerRule.magnitude(hit, settings: settings) == 0)
        hit.kind = .power
        #expect(StaggerRule.magnitude(hit, settings: settings) == 1)
    }

    @Test func aShieldBashScalesWithTheShieldRating() {
        var hit = StaggerHit(weaponStagger: 0)
        hit.kind = .bash(shieldRating: 30)
        #expect(abs(StaggerRule.magnitude(hit, settings: settings) - 0.04) < 0.0001)
    }

    @Test func aWeaponBashScalesByTheBashersBlockSkill() {
        var hit = StaggerHit(weaponStagger: 1)
        hit.kind = .bash(shieldRating: nil)
        hit.attackerBlockSkill = 100
        #expect(abs(StaggerRule.magnitude(hit, settings: settings) - 0.99) < 0.0001)
    }

    @Test func theBlockRecoilGrowsWithTheBlockersSkill() {
        let recoil = StaggerRule.blockRecoil(blockerSkill: 50, settings: settings)
        #expect(abs(recoil - 0.251) < 0.0001)
    }

    @Test func theChanceAndTheMinimumGateAStagger() {
        #expect(StaggerRule.staggers(magnitude: 0.5, roll: 49, settings: settings))
        #expect(!StaggerRule.staggers(magnitude: 0.5, roll: 50, settings: settings))
        #expect(!StaggerRule.staggers(magnitude: 0, roll: 0, settings: settings))
    }

    @Test func malformedInputDoesNotStagger() {
        var hit = StaggerHit(weaponStagger: .nan)
        hit.perkMultiplier = .infinity
        #expect(StaggerRule.magnitude(hit, settings: settings) == 0)
    }
}
