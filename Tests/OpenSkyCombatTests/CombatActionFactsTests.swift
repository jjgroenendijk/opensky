// The combat state that conditions read: melee phases and NPC behaviour phases map
// onto `ActorActionFacts`.

import Foundation
import OpenSkyActorsInterface
@testable import OpenSkyCombat
import Testing

struct CombatActionFactsTests {
    @Test func meleePhasesMapOntoAttackStates() {
        #expect(MeleeAttackPhase.idle.attackState == .none)
        #expect(MeleeAttackPhase.windup.attackState == .draw)
        #expect(MeleeAttackPhase.swinging.attackState == .swing)
        #expect(MeleeAttackPhase.contact.attackState == .hit)
        #expect(MeleeAttackPhase.recovery.attackState == .followThrough)
    }

    @Test func bowShotPhasesMapOntoTheBowAttackStates() {
        #expect(ArcheryShotPhase.idle.attackState == .none)
        #expect(ArcheryShotPhase.nocked.attackState == .drawingBow)
        #expect(ArcheryShotPhase.drawing.attackState == .drawingBow)
        #expect(ArcheryShotPhase.drawn.attackState == .holdingBowDrawn)
        #expect(ArcheryShotPhase.loosed.attackState == .loosingArrow)
        #expect(ActorAttackState.loosingArrow.rawValue == 12)
    }

    @Test func thePlayerGuardAndStaggerComeFromTheGraphEvents() {
        var state = MeleeCombatState()
        state.handle(CombatGraphNames.blockStart)
        #expect(state.actionFacts.isBlocking)
        #expect(state.actionFacts.wantsBlocking)
        #expect(!state.actionFacts.isStaggered)
    }

    @Test func behaviourPhasesMapOntoActionFacts() {
        #expect(CombatBehaviorPhase.blocking.actionFacts.isBlocking)
        #expect(CombatBehaviorPhase.fleeing.actionFacts.isFleeing)
        #expect(CombatBehaviorPhase.staggered.actionFacts.isStaggered)
        #expect(CombatBehaviorPhase.windup.actionFacts.attackState == .draw)
        #expect(CombatBehaviorPhase.approaching.actionFacts == .still)
    }

    /// The side keyword covers both sides.
    @Test func eachPowerAttackDirectionNamesItsAttackType() {
        #expect(MeleePowerDirection.inPlace.attackTypeKeyword == "PowerAttackTypeStanding")
        #expect(MeleePowerDirection.forward.attackTypeKeyword == "PowerAttackTypeForward")
        #expect(MeleePowerDirection.backward.attackTypeKeyword == "PowerAttackTypeBack")
        #expect(MeleePowerDirection.left.attackTypeKeyword == "PowerAttackTypeSide")
        #expect(MeleePowerDirection.right.attackTypeKeyword == "PowerAttackTypeSide")
    }
}
