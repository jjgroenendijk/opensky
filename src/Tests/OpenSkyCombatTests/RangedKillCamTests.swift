// The release check of a bow or crossbow kill cam: the gates, the sure passes, and the
// chance from the distance and the bonuses. Source: docs/engine/kill-cam.md.

@testable import OpenSkyCombat
import Testing

struct RangedKillCamTests {
    private static func facts(distance: Float = 1500) -> RangedKillCamFacts {
        var facts = RangedKillCamFacts()
        facts.distance = distance
        facts.draw = 1
        facts.targetLevel = 10
        facts.playerLevel = 10
        facts.targetIsHostileThreat = false
        return facts
    }

    @Test func theDocumentedExampleGivesFiftyPercent() {
        #expect(RangedKillCam.chance(Self.facts()) == 50)
        #expect(RangedKillCam.plays(Self.facts(), roll: 49))
        #expect(!RangedKillCam.plays(Self.facts(), roll: 50))
    }

    @Test func farTargetsHigherLevelsAndLowHealthPassAtOnce() {
        #expect(RangedKillCam.chance(Self.facts(distance: 2500)) == nil)
        var strong = Self.facts()
        strong.targetLevel = 11
        #expect(RangedKillCam.chance(strong) == nil)
        var hurt = Self.facts()
        hurt.playerHealthShare = 0.04
        #expect(RangedKillCam.chance(hurt) == nil)
        #expect(RangedKillCam.plays(hurt, roll: 99))
    }

    @Test func theBonusesLowerTheChance() {
        var sneak = Self.facts()
        sneak.undetectedSneakShot = true
        #expect(RangedKillCam.chance(sneak) == 40)
        var threat = Self.facts()
        threat.targetIsHostileThreat = true
        #expect(RangedKillCam.chance(threat) == 60)
        var weak = Self.facts()
        weak.targetLevel = 2
        #expect(RangedKillCam.chance(weak) == 40)
    }

    @Test func eachGateStopsTheKillCam() {
        var two = Self.facts()
        two.enemiesInCombat = 2
        var alive = Self.facts()
        alive.hitKills = false
        var dead = Self.facts()
        dead.targetAlive = false
        var blocked = Self.facts()
        blocked.clearLine = false
        var weakDraw = Self.facts()
        weakDraw.draw = 0.7
        for facts in [two, alive, dead, blocked, weakDraw] {
            #expect(!RangedKillCam.plays(facts, roll: 0))
        }
        var crossbow = Self.facts()
        crossbow.draw = nil
        #expect(RangedKillCam.plays(crossbow, roll: 0))
    }
}
