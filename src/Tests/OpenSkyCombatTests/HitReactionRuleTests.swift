// The game's hit reaction rule: the stagger magnitude, the roll, the large recoil of
// a bash, and the block hit (docs/engine/hit-reactions.md).

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import Testing

struct HitReactionRuleTests {
    private let settings = StaggerSettings.vanilla

    private func hit(stagger: Float, block: Float = 0, mass: Float = 1) -> HitReactionHit {
        var hit = HitReactionHit()
        hit.facts.attackStagger = stagger
        hit.facts.attackerBlock = block
        hit.facts.targetMass = mass
        return hit
    }

    /// The page's example: 40 Block, a shield bash, a running target of mass 1.
    @Test func theMagnitudeFollowsTheDocumentedExample() {
        var bash = hit(stagger: 1, block: 40)
        bash.bashesWithShield = true
        bash.facts.targetRuns = true
        #expect(abs(HitReactionRule.magnitude(bash) - 1.35) < 0.0001)
    }

    @Test func theWeaponFactorDependsOnTheWeapon() {
        var sword = hit(stagger: 1)
        sword.handType = .sword
        #expect(HitReactionRule.weaponFactor(sword) == 0.2)
        sword.handType = .greatsword
        #expect(HitReactionRule.weaponFactor(sword) == 0.5)
        sword.handType = .bow
        #expect(HitReactionRule.weaponFactor(sword) == 0.5)
        #expect(HitReactionRule.weaponFactor(hit(stagger: 1)) == 1)
    }

    @Test func aHeavyOrBlockingTargetStaggersLess() {
        #expect(HitReactionRule.magnitude(hit(stagger: 1, mass: 2)) == 0.25)
        var blocked = hit(stagger: 1)
        blocked.wasBlocked = true
        #expect(HitReactionRule.magnitude(blocked) == 0)
        var recoiling = hit(stagger: 1)
        recoiling.facts.targetRecoils = true
        #expect(HitReactionRule.magnitude(recoiling) == 0.75)
        #expect(HitReactionRule.magnitude(hit(stagger: .nan)) == 0)
    }

    @Test func aHitStaggersOnTheRollAndIsCutToOne() {
        let strong = hit(stagger: 4)
        #expect(HitReactionRule.reaction(strong, roll: 49, settings: settings)
            .staggerMagnitude == 1)
        #expect(HitReactionRule.reaction(strong, roll: 50, settings: settings)
            .staggerMagnitude == nil)
        let none = hit(stagger: 0)
        #expect(HitReactionRule.reaction(none, roll: 0, settings: settings).staggerMagnitude == nil)
    }

    @Test func thePlayerAndARangedWeaponStaggerWithNoRoll() {
        var onPlayer = hit(stagger: 1)
        onPlayer.isPlayerTarget = true
        #expect(HitReactionRule.reaction(onPlayer, roll: 99, settings: settings)
            .staggerMagnitude != nil)
        var calm = settings
        calm.playerAlwaysStaggered = false
        #expect(HitReactionRule.reaction(onPlayer, roll: 99, settings: calm)
            .staggerMagnitude == nil)
        var arrow = hit(stagger: 1)
        arrow.handType = .bow
        #expect(HitReactionRule.reaction(arrow, roll: 99, settings: settings)
            .staggerMagnitude != nil)
    }

    @Test func aBashStaggersWithNoRollUnlessTheTargetStartsAnAttack() {
        var bash = hit(stagger: 1)
        bash.isBash = true
        let plain = HitReactionRule.reaction(bash, roll: 99, settings: settings)
        #expect(!plain.largeRecoil)
        #expect(plain.staggerMagnitude != nil)

        bash.facts.targetAttacks = true
        let interrupting = HitReactionRule.reaction(bash, roll: 0, settings: settings)
        #expect(interrupting.largeRecoil)
        #expect(interrupting.staggerMagnitude == nil)

        bash.facts.targetAttacks = false
        bash.wasBlocked = true
        let blocked = HitReactionRule.reaction(bash, roll: 0, settings: settings)
        #expect(blocked.blockHit && !blocked.attackerRecoils)
    }

    @Test func aBlockedMeleeHitRecoilsItsAttacker() {
        var blocked = hit(stagger: 1)
        blocked.wasBlocked = true
        let reaction = HitReactionRule.reaction(blocked, roll: 0, settings: settings)
        #expect(reaction.blockHit)
        #expect(reaction.attackerRecoils)
        #expect(reaction.staggerMagnitude == nil)
        blocked.isMelee = false
        #expect(!HitReactionRule.reaction(blocked, roll: 0, settings: settings).attackerRecoils)
    }

    @Test func theDirectionIsAPartOfAFullTurn() {
        #expect(HitReactionFacts.direction(targetFacing: 0, target: .zero, attacker: nil) == 0)
        let ahead = HitReactionFacts.direction(
            targetFacing: 0, target: .zero, attacker: SIMD3(100, 0, 0)
        )
        #expect(ahead == 0)
        let right = HitReactionFacts.direction(
            targetFacing: 0, target: .zero, attacker: SIMD3(0, -100, 0)
        )
        #expect(abs(right - 0.25) < 0.0001)
    }
}
