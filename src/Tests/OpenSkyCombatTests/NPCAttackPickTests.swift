// Which ATKD attack an NPC starts. Rules: docs/engine/attack-data.md ("The AI's pick").

@testable import OpenSkyCombat
import OpenSkyFormatsESM
import Testing

struct NPCAttackPickTests {
    private static func attack(
        _ event: String, chance: Float = 1, flags: RaceAttack.Flags = [],
        recovery: Float = 0, strikeAngle: Float = 35
    ) -> RaceAttack {
        var properties = RaceAttack.Properties()
        properties.attackChance = chance
        properties.flags = flags
        properties.recoveryTime = recovery
        properties.strikeAngle = strikeAngle
        return RaceAttack(properties: properties, event: event)
    }

    @Test func theGeneralPoolLeavesOutBashAndLeftHand() {
        let list = [
            Self.attack("attackStart"), Self.attack("bashStart", flags: .bash),
            Self.attack("attackStartLeftHand", flags: .leftHand)
        ]
        let general = NPCAttackPick.candidates(
            list, situation: NPCAttackSituation()
        )
        #expect(general.map(\.attack.event) == ["attackStart"])
        var situation = NPCAttackSituation()
        situation.pool = .leftHand
        let left = NPCAttackPick.candidates(list, situation: situation)
        #expect(left.map(\.attack.event) == ["attackStartLeftHand"])
    }

    @Test func recoveryAndStaminaKeepAnAttackOut() {
        let list = [
            Self.attack("attackStart", recovery: 2),
            Self.attack("attackPowerStart", flags: .powerAttack)
        ]
        var situation = NPCAttackSituation()
        situation.secondsSinceUse = ["attackstart": 1]
        situation.stamina = 0
        let options = NPCAttackPick.candidates(
            list, situation: situation
        )
        #expect(options.isEmpty)
        situation.secondsSinceUse = ["attackstart": 3]
        #expect(NPCAttackPick.candidates(list, situation: situation)
            .map(\.attack.event) == ["attackStart"])
    }

    @Test func aStaggeredTargetWeighsByTheStyle() {
        var situation = NPCAttackSituation()
        situation.weights.powerAttackStaggered = 3
        situation.weights.attackStaggered = 0.5
        situation.targetIsStaggered = true
        let options = NPCAttackPick.candidates(
            [Self.attack("attackStart"), Self.attack("attackPowerStart", flags: .powerAttack)],
            situation: situation
        )
        #expect(options.map(\.weight) == [0.5, 3])
        situation.targetIsStaggered = false
        situation.targetBlocksTowardAttacker = true
        situation.weights.powerAttackBlocking = 0
        #expect(NPCAttackPick.candidates(
            [Self.attack("attackPowerStart", flags: .powerAttack)], situation: situation
        ).isEmpty)
    }

    /// Weights 1 and 0.5: a draw into the second, then a failed second roll, removes it
    /// and the next draw takes the first.
    @Test func aFailedSecondRollRemovesTheAttack() {
        let list = [Self.attack("attackStart"), Self.attack("attackPowerStart", chance: 0.5)]
        var rolls: [Float] = [0.9, 0.8, 0.1, 0.1]
        let chosen = NPCAttackPick.choose(
            list, situation: NPCAttackSituation(),
            aim: (0, 0), roll: { rolls.removeFirst() }
        )
        #expect(chosen?.event == "attackStart")
        #expect(rolls.isEmpty)
    }

    @Test func aTargetOutsideTheConeFailsEveryAttack() {
        let list = [Self.attack("attackStart", strikeAngle: 30)]
        let outside = NPCAttackPick.choose(
            list, situation: NPCAttackSituation(),
            aim: (0, .pi / 6), roll: { 0 }
        )
        #expect(outside == nil)
        let inside = NPCAttackPick.choose(
            list, situation: NPCAttackSituation(),
            aim: (0, .pi / 12), roll: { 0 }
        )
        #expect(inside?.event == "attackStart")
    }

    @Test func aRotatingAttackIgnoresItsAttackAngle() {
        var data = RaceAttack.Properties()
        data.attackAngle = 90
        #expect(!NPCAttackPick.isInCone(data, heading: 0, directionToTarget: 0, mult: 1))
        data.flags = .rotating
        #expect(NPCAttackPick.isInCone(data, heading: 0, directionToTarget: 0, mult: 1))
    }

    @Test func theStyleGivesTheWeights() {
        #expect(NPCAttackWeights(style: nil) == NPCAttackWeights())
        #expect(CombatStyleTuning.neutral.attackWeights == NPCAttackWeights())
    }
}
