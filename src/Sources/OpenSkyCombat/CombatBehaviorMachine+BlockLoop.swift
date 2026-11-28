// The machine's side of the block loop: a pass every 0.25 s while spacing, a raised guard
// that bashes and drops by its rules, and the per-gap block roll of an actor without a
// style. See docs/engine/combat-blocking.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions

nonisolated extension CombatBehaviorMachine {
    /// Enters the gap between attacks. A styled actor goes back to a guard a bash left;
    /// any other actor rolls its block chance once here, so the chance is per attack cycle.
    mutating func enterSpacing() -> CombatBehaviorStep {
        if settings.blockLoop != nil {
            enter(blockLoop.raised == nil ? .spacing : .blocking)
            var step = unchanged()
            step.command = command(.hold)
            return step
        }
        let roll = Float(random.percent()) / 100
        guard roll < settings.blockChance else {
            enter(.spacing)
            var step = unchanged()
            step.command = command(.hold)
            return step
        }
        blockCount += 1
        enter(.blocking)
        var step = unchanged()
        step.raisedBlock = true
        step.command = command(.hold)
        return step
    }

    mutating func advanceBlocking(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        if let loop = settings.blockLoop {
            return advanceGuard(inputs, loop: loop)
        }
        guard phaseSeconds >= settings.blockSeconds, inputs.weaponOut else { return unchanged() }
        guard inputs.distance <= inputs.holdDistance(settings: settings) else {
            enter(.approaching)
            return approach(inputs)
        }
        return startAttackOrCast(inputs)
    }

    /// One pass of the loop while spacing: the block attack, the offensive bash, then the
    /// block. Nil when no pass is due or nothing started.
    mutating func blockLoopPass(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep? {
        guard
            let loop = settings.blockLoop, inputs.archery == nil, inputs.weaponOut,
            blockLoop.untilPass <= 0 else { return nil }
        blockLoop.untilPass = loop.passSeconds
        let rules = CombatBlockRules(settings: loop, inputs: inputs)
        if rules.mayStartBlockAttack, unitRoll() < loop.blockAttackChance {
            return raiseGuard(.blockAttack, hold: loop.blockAttackSeconds.lerp(unitRoll()), loop)
        }
        if inputs.canBash, unitRoll() < loop.offensiveBashChance * rules.bashTargetMult {
            return startBash()
        }
        if rules.mayStartBlock, unitRoll() < loop.blockChance {
            return raiseGuard(.block, hold: loop.blockSeconds, loop)
        }
        return nil
    }

    /// The bash pick found no attack: the actor goes back to where the bash started.
    public mutating func cancelBash() {
        guard blockLoop.isBashing, phase == .windup else { return }
        blockLoop.cancelBash()
        enter(blockLoop.raised == nil ? .spacing : .blocking)
    }

    /// The raised guard's kind, for the readout.
    public var guardKind: String? {
        phase == .blocking ? blockLoop.raised?.kind.rawValue : nil
    }

    /// Guards raised and bashes started by the block loop since construction.
    public var loopGuardCount: Int {
        blockLoop.guardCount
    }

    public var bashCount: Int {
        blockLoop.bashCount
    }

    /// Whether the attack under way is a bash.
    public var isBashing: Bool {
        blockLoop.isBashing
    }

    /// A guard lasts only through blocking and a bash from it; a bash ends with its attack.
    mutating func keepBlockLoop(entering next: CombatBehaviorPhase) {
        let attacking = [.windup, .contact, .recovery].contains(next)
        if !attacking {
            blockLoop.isBashing = false
        }
        if next != .blocking, !(attacking && blockLoop.isBashing) {
            blockLoop.raised = nil
        }
    }

    // MARK: - Private

    /// A held guard: a bash roll every pass, the attack roll with its blocking terms, and
    /// the stop rules. The guard never drops while the target attacks the actor.
    private mutating func advanceGuard(
        _ inputs: CombatBehaviorInputs, loop: CombatBlockLoopSettings
    ) -> CombatBehaviorStep {
        guard var raised = blockLoop.raised else { return dropGuard(inputs) }
        let rules = CombatBlockRules(settings: loop, inputs: inputs)
        if raised.elapsed >= raised.nextBashRoll {
            raised.nextBashRoll += loop.passSeconds
            blockLoop.raised = raised
            if inputs.canBash, unitRoll() < loop.bashChance * rules.bashTargetMult {
                return startBash()
            }
        }
        if
            inputs.distance <= inputs.holdDistance(settings: settings), inputs.weaponOut,
            rollsAttack(inputs)
        {
            blockLoop.raised = nil
            return startAttackOrCast(inputs)
        }
        if raised.kind == .block, raised.elapsed >= raised.nextStopCheck {
            raised.nextStopCheck = raised.elapsed + loop.stopCheckSeconds
            raised.isFar = rules.isPastStopDistance
        }
        blockLoop.raised = raised
        let wantsStop = raised.elapsed >= raised.holdSeconds || raised.isFar
            || (raised.kind == .blockAttack && inputs.targetIsStaggered)
        guard wantsStop, !rules.targetAttacksActor else { return unchanged() }
        return dropGuard(inputs)
    }

    private mutating func dropGuard(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        blockLoop.raised = nil
        guard inputs.distance <= inputs.holdDistance(settings: settings) else {
            enter(.approaching)
            return approach(inputs)
        }
        enter(.spacing)
        var step = unchanged()
        step.command = command(.hold)
        return step
    }

    private mutating func raiseGuard(
        _ kind: CombatBlockLoop.GuardKind, hold: Float, _ loop: CombatBlockLoopSettings
    ) -> CombatBehaviorStep {
        blockLoop.raise(kind, holdSeconds: hold, settings: loop)
        blockCount += 1
        enter(.blocking)
        var step = unchanged()
        step.raisedBlock = true
        step.command = command(.hold)
        return step
    }

    private mutating func startBash() -> CombatBehaviorStep {
        blockLoop.startBash()
        enter(.windup)
        var step = unchanged()
        step.startedAttack = true
        step.startedBash = true
        step.command = command(.hold)
        return step
    }

    /// Finer than a percent roll, because the bash chances are a few percent.
    private mutating func unitRoll() -> Float {
        Float(random.next() % 10000) / 10000
    }
}
