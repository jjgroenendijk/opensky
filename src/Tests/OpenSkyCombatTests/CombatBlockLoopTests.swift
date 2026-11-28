// The block loop of a styled actor: guards, block attacks, bashes, the blocking terms of
// the attack chance, and the stop rules. Rules: docs/engine/combat-blocking.md.

@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import simd
import Testing

@MainActor
struct CombatBlockLoopTests {
    private typealias Fixture = CombatBehaviorFixture

    /// A styled actor that never attacks, with the loop chances given.
    private static func machine(
        block: Float = 0, blockAttack: Float = 0, bash: Float = 0, offensiveBash: Float = 0,
        blockSeconds: Float = 0.5
    ) -> CombatBehaviorMachine {
        var loop = CombatBlockLoopSettings()
        loop.blockChance = block
        loop.blockAttackChance = blockAttack
        loop.bashChance = bash
        loop.offensiveBashChance = offensiveBash
        loop.blockSeconds = blockSeconds
        var settings = Fixture.neverCasting
        settings.attackChance = 0
        settings.blockLoop = loop
        return Fixture.machine(settings: settings)
    }

    /// The actor stands on +x and the target at the origin faces it.
    private static func inputs(
        attack: CombatTargetActions.Attack = .none, canBash: Bool = false
    ) -> CombatBehaviorInputs {
        var inputs = Fixture.inputs()
        inputs.canBlock = true
        inputs.canBash = canBash
        inputs.targetYaw = 0
        inputs.target.attack = attack
        inputs.target.reach = 100
        return inputs
    }

    @Test func theStyleValuesGiveTheLoopChancesTimesAndDistances() {
        let low = CombatBlockLoopSettings(
            offensive: 0.5, defensive: 0.24, bash: CombatBashTargetMults()
        )
        #expect(abs(low.blockSeconds - 5.92) < 0.001)
        #expect(abs(low.blockStartDistance - 70.4) < 0.001)
        #expect(abs(low.blockStopDistance - 189.44) < 0.001)
        #expect(abs(low.attackChanceBlockingMult - 0.5572) < 0.001)
        #expect(abs(low.bashChance - 0.067) < 0.001)
        #expect(abs(low.offensiveBashChance - 0.025) < 0.001)
        let high = CombatBlockLoopSettings(
            offensive: 0.5, defensive: 0.75, bash: CombatBashTargetMults()
        )
        #expect(abs(high.blockSeconds - 5004) < 0.01)
        #expect(CombatBlockLoopSettings.threePointLerp(4, 8, 10000, at: .nan) == 8)
        let tuned = CombatBehaviorSettings.standard.tuned(by: .neutral)
        #expect(tuned.blockLoop == CombatBlockLoopSettings(
            offensive: 0.5, defensive: 0.5, bash: CombatBashTargetMults()
        ))
        #expect(CombatBehaviorSettings.standard.blockLoop == nil)
    }

    @Test func aGuardHoldsThroughASwingAtTheBlockerAndDropsAfter() {
        var machine = Self.machine(block: 1)
        Fixture.run(&machine, until: { $0.phase == .blocking }, inputs: Self.inputs())
        #expect(machine.guardKind == "block")
        #expect(machine.loopGuardCount == 1)
        Fixture.run(&machine, seconds: 1, inputs: Self.inputs(attack: .swing))
        #expect(machine.phase == .blocking)
        _ = machine.step(seconds: Fixture.step, inputs: Self.inputs())
        #expect(machine.phase == .spacing)
        #expect(machine.guardKind == nil)
    }

    @Test func noBlockStartsAgainstARetreatingBlockingOrRangedTarget() {
        var away = Self.inputs()
        away.targetVelocity = SIMD3(-200, 0, 0)
        var blocking = Self.inputs()
        blocking.target.isBlocking = true
        var archer = Self.inputs()
        archer.target.fightsInMelee = false
        var behind = Self.inputs()
        behind.targetYaw = .pi
        var unarmed = Self.inputs()
        unarmed.canBlock = false
        for inputs in [away, blocking, archer, behind, unarmed] {
            var machine = Self.machine(block: 1)
            Fixture.run(&machine, seconds: 2, inputs: inputs)
            #expect(machine.loopGuardCount == 0)
        }
    }

    @Test func aBlockAttackAnswersADrawAndHoldsOneToTwoSeconds() {
        var machine = Self.machine(blockAttack: 1)
        let draw = Self.inputs(attack: .draw, canBash: true)
        Fixture.run(&machine, until: { $0.phase == .blocking }, inputs: draw)
        #expect(machine.guardKind == "blockAttack")
        let held = Fixture.run(
            &machine, until: { $0.phase != .blocking }, limit: 3, inputs: Self.inputs()
        )
        let seconds = Float(held.count) * Fixture.step
        #expect(seconds >= 0.9 && seconds <= 2.1)
    }

    @Test func aBashFromAGuardReturnsToTheGuard() {
        var machine = Self.machine(block: 1, bash: 1, blockSeconds: 30)
        let inputs = Self.inputs(canBash: true)
        Fixture.run(&machine, until: { $0.phase == .blocking }, inputs: inputs)
        let steps = Fixture.run(&machine, until: { $0.isBashing }, limit: 1, inputs: inputs)
        #expect(steps.last?.startedBash == true)
        #expect(steps.last?.startedAttack == true)
        #expect(machine.bashCount == 1)
        Fixture.run(&machine, until: { !$0.isBashing }, limit: 3, inputs: inputs)
        #expect(machine.phase == .blocking)
        #expect(machine.loopGuardCount == 1)
    }

    @Test func anOffensiveBashTheRuntimeCannotPickGoesBackToSpacing() {
        var machine = Self.machine(offensiveBash: 1)
        let inputs = Self.inputs(canBash: true)
        Fixture.run(&machine, until: { $0.isBashing }, inputs: inputs)
        #expect(machine.phase == .windup)
        machine.cancelBash()
        #expect(machine.phase == .spacing)
        #expect(machine.bashCount == 0)
        #expect(!machine.isBashing)
    }

    @Test func aBlockingActorAttacksLessAndNeverIntoASwing() {
        var settings = Self.machine(block: 1, blockSeconds: 30).settings
        settings.attackChance = 1
        settings.attackRollSeconds = 100
        var styled = CombatBehaviorMachine(settings: settings, seed: 1)
        Fixture.run(&styled, until: { $0.phase == .blocking }, inputs: Self.inputs())
        let loop = settings.blockLoop ?? CombatBlockLoopSettings()
        #expect(abs(styled.attackChance(Self.inputs()) - loop.attackChanceBlockingMult) < 0.001)
        #expect(styled.attackChance(Self.inputs(attack: .swing)) == 0)
        var staggered = Self.inputs(attack: .swing)
        staggered.targetIsStaggered = true
        #expect(styled.attackChance(staggered) == 1)
    }

    @Test func aTargetWalkingPastTheStopDistanceEndsTheBlock() {
        var machine = Self.machine(block: 1, blockSeconds: 30)
        Fixture.run(&machine, until: { $0.phase == .blocking }, inputs: Self.inputs())
        var far = Self.inputs()
        far.targetVelocity = SIMD3(-1000, 0, 0)
        Fixture.run(&machine, until: { $0.phase != .blocking }, limit: 2, inputs: far)
        #expect(machine.phase == .spacing)
    }

    @Test func theBashChanceFollowsTheTargetsState() {
        var mults = CombatBashTargetMults()
        mults.recoil = 2
        mults.powerAttack = 3
        mults.attack = 4
        var settings = CombatBlockLoopSettings()
        settings.bashTargetMults = mults
        var inputs = Self.inputs()
        #expect(CombatBlockRules(settings: settings, inputs: inputs).bashTargetMult == 1)
        inputs.target.isBlocking = true
        #expect(CombatBlockRules(settings: settings, inputs: inputs).bashTargetMult == 0)
        inputs.target.attack = .swing
        #expect(CombatBlockRules(settings: settings, inputs: inputs).bashTargetMult == 4)
        inputs.target.isPowerAttack = true
        #expect(CombatBlockRules(settings: settings, inputs: inputs).bashTargetMult == 3)
        inputs.target.isRecoiling = true
        #expect(CombatBlockRules(settings: settings, inputs: inputs).bashTargetMult == 2)
    }
}
