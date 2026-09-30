// One actor's combat mind, as a pure value over a fixed step. Each step it
// checks, in order: target still there, hurt enough to flee, target still seen,
// close enough to swing. No clock: the block roll draws from a `ConditionRandom`
// seeded from the `ReferenceKey`. It asks the NPC mover for movement through
// `CombatMovementCommand` rather than writing positions.
// See docs/engine/combat-behavior.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyConditions
import simd

/// The decision layer for one actor in one fight.
nonisolated public struct CombatBehaviorMachine: Equatable, Sendable {
    public let settings: CombatBehaviorSettings

    public private(set) var phase = CombatBehaviorPhase.idle
    /// Seconds spent in the current phase.
    public private(set) var phaseSeconds: Float = 0
    /// Fights entered, attacks started, contact steps reached, guards raised and
    /// searches begun since construction. The panel reads all five; the first
    /// two differ only by an attack a stagger interrupted before it connected.
    public private(set) var fightCount = 0
    public private(set) var attackCount = 0
    public private(set) var contactCount = 0
    public private(set) var blockCount = 0
    public private(set) var searchCount = 0
    /// Casts begun since construction, which differs from casts released by the
    /// ones a stagger or a retreat interrupted.
    public private(set) var castCount = 0

    /// The spell being charged right now, or nil when nothing is. Readable so
    /// the runtime can drop the cast behind a stagger or a park, which happen
    /// outside `step(seconds:inputs:)`.
    public private(set) var pendingCast: CombatSpellOption?

    /// Seeded per actor, drawn from only for the block roll.
    private var random: ConditionRandom
    /// Seconds since the last movement command, so a chase re-paths on the
    /// stated interval rather than every step.
    private var secondsSinceCommand: Float = 0

    public init(settings: CombatBehaviorSettings = .standard, seed: UInt64) {
        self.settings = settings
        random = ConditionRandom(seed: seed)
    }

    /// Whether this actor counts as being in the fight.
    public var isEngaged: Bool {
        phase.isEngaged
    }

    /// What this actor is blocking with, or nil when its guard is down.
    ///
    /// Always `.weapon`: an actor blocking with a shield needs the equipment
    /// resolution that would tell it apart from a raised sword, and reporting
    /// `.shield` without one would move the damage reduction to a different
    /// pinned constant on a guess. Stated in docs/engine/combat-behavior.md.
    public var blockKind: MeleeBlockKind? {
        phase == .blocking ? .weapon : nil
    }

    /// Advances by exactly one fixed step and reports what it did.
    ///
    /// A cast in flight is dropped in exactly one place: here, whenever a step
    /// left the casting phase without releasing. Fleeing, losing the target and
    /// giving up all reach that line, so no exit has to remember to clean up
    /// after a charge it did not start.
    public mutating func step(seconds: Float, inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard seconds > 0, seconds.isFinite else { return unchanged() }
        phaseSeconds += seconds
        secondsSinceCommand += seconds
        var step = advance(inputs)
        // A released cast cleared `pendingCast` itself, so what is left here is
        // exactly a charge the machine walked away from.
        step.cancelledCast = pendingCast != nil && phase != .casting
        pendingCast = phase == .casting ? pendingCast : nil
        return step
    }

    private mutating func advance(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard inputs.isTargetAlive else {
            return phase.isEngaged ? endPursuit() : unchanged()
        }
        switch phase {
        case .idle, .disengaged: return advanceWaiting(inputs)
        case .staggered: return advanceStaggered()
        case .fleeing: return advanceFleeing(inputs)
        case .searching: return advanceSearching(inputs)
        default: return advanceFighting(inputs)
        }
    }

    /// Interrupts whatever is in flight, as the graph's stagger does. An actor that
    /// was not fighting is engaged afterwards: being struck reveals the attacker.
    /// - Returns: true when the machine entered a stagger, so a caller asks for a
    ///   clip only when there is one to play.
    @discardableResult
    public mutating func stagger() -> Bool {
        guard phase != .staggered else { return false }
        if !phase.isEngaged {
            fightCount += 1
        }
        pendingCast = nil
        enter(.staggered)
        return true
    }

    /// Drops a charge the world refused to start, without ending the fight:
    /// the actor lands in the gap between attacks and decides again from there.
    public mutating func abandonCast() {
        guard phase == .casting else { return }
        pendingCast = nil
        enter(.spacing)
    }

    /// Ends the fight outright without touching the counts, for `StopCombat`
    /// and for an actor whose cell unloaded.
    public mutating func park() {
        pendingCast = nil
        enter(.idle)
        secondsSinceCommand = 0
    }

    // MARK: - Waiting

    /// Not in a fight: engage when the target is perceived or a script says so.
    /// Hostility itself is still entered only by a blow, the panel, or a script. An
    /// actor under the flee threshold does not start a fight.
    private mutating func advanceWaiting(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard !inputs.shouldFlee(settings: settings) else { return unchanged() }
        guard inputs.isForced || inputs.awareness.isDetected else { return unchanged() }
        fightCount += 1
        enter(.approaching)
        var step = unchanged()
        step.startedFight = true
        step.command = command(.approach(inputs.targetPosition))
        return step
    }

    // MARK: - Fighting

    /// Approaching, spacing, blocking or attacking: the phases that mean "I
    /// have my target and I am working on it".
    private mutating func advanceFighting(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        if inputs.shouldFlee(settings: settings) {
            return enterFlee(inputs)
        }
        if !inputs.awareness.isDetected, !inputs.isForced {
            return enterSearch(inputs)
        }
        switch phase {
        case .approaching: return advanceApproaching(inputs)
        case .spacing: return advanceSpacing(inputs)
        case .blocking: return advanceBlocking(inputs)
        case .casting: return advanceCasting()
        case .windup: return advanceWindup()
        case .contact:
            enter(.recovery)
            return unchanged()
        case .recovery:
            return phaseSeconds >= settings.recoverySeconds ? enterSpacing() : unchanged()
        default: return unchanged()
        }
    }

    /// Closing: a caster that is already in range of something it can pay for
    /// casts from where it stands rather than walking into sword reach first,
    /// which is the one decision that makes a mage read as a mage.
    private mutating func advanceApproaching(
        _ inputs: CombatBehaviorInputs
    ) -> CombatBehaviorStep {
        guard inputs.distance > inputs.strikingDistance(settings: settings)
        else { return enterSpacing() }
        if let option = inputs.castableSpell {
            return startCast(option)
        }
        guard secondsSinceCommand >= settings.commandIntervalSeconds else { return unchanged() }
        var step = unchanged()
        step.command = command(.approach(inputs.targetPosition))
        return step
    }

    private mutating func advanceSpacing(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard inputs.distance <= inputs.strikingDistance(settings: settings) else {
            enter(.approaching)
            var step = unchanged()
            step.command = command(.approach(inputs.targetPosition))
            return step
        }
        guard phaseSeconds >= settings.attackIntervalSeconds else { return unchanged() }
        return startAttackOrCast(inputs)
    }

    private mutating func advanceBlocking(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard phaseSeconds >= settings.blockSeconds else { return unchanged() }
        guard inputs.distance <= inputs.strikingDistance(settings: settings) else {
            enter(.approaching)
            var step = unchanged()
            step.command = command(.approach(inputs.targetPosition))
            return step
        }
        return startAttackOrCast(inputs)
    }

    /// The one place a swing and a cast are chosen between
    /// (docs/engine/combat-behavior.md). Out of weapon reach, cast when affordable;
    /// in reach, cast with probability `castChance`. Uses the seeded block-roll RNG.
    private mutating func startAttackOrCast(
        _ inputs: CombatBehaviorInputs
    ) -> CombatBehaviorStep {
        guard let option = inputs.castableSpell else { return startAttack() }
        guard inputs.distance <= inputs.strikingDistance(settings: settings)
        else { return startCast(option) }
        let roll = Float(random.percent()) / 100
        return roll < settings.castChance ? startCast(option) : startAttack()
    }

    private mutating func startCast(_ option: CombatSpellOption) -> CombatBehaviorStep {
        castCount += 1
        pendingCast = option
        enter(.casting)
        var step = unchanged()
        step.startedCast = option
        step.command = command(.hold)
        return step
    }

    /// Charging, and for a maintained spell holding it afterwards. The charge is the
    /// record's `chargeTime`; the hold time is ours. A target leaving range does not
    /// cancel the cast.
    private mutating func advanceCasting() -> CombatBehaviorStep {
        guard let option = pendingCast else { return enterSpacing() }
        let hold = max(0, option.chargeSeconds)
            + (option.isConcentration ? settings.concentrationSeconds : 0)
        guard phaseSeconds >= hold else { return unchanged() }
        pendingCast = nil
        enter(.recovery)
        var step = unchanged()
        step.releasedCast = option
        return step
    }

    private mutating func advanceWindup() -> CombatBehaviorStep {
        guard phaseSeconds >= settings.windupSeconds else { return unchanged() }
        contactCount += 1
        enter(.contact)
        var step = unchanged()
        step.reachedContact = true
        return step
    }

    private mutating func advanceStaggered() -> CombatBehaviorStep {
        guard phaseSeconds >= settings.staggerSeconds else { return unchanged() }
        // Straight to spacing rather than to a fresh gap: the distance check at
        // the top of `advanceSpacing` sends it back to approaching if the target
        // used the stagger to walk away.
        enter(.spacing)
        return unchanged()
    }

    private mutating func startAttack() -> CombatBehaviorStep {
        attackCount += 1
        enter(.windup)
        var step = unchanged()
        step.startedAttack = true
        return step
    }

    /// Enters the gap between attacks, either waiting it out or spending it
    /// with the guard up. Rolled once here rather than once per step, so the
    /// stated probability is per attack cycle and not per sixtieth of a second.
    private mutating func enterSpacing() -> CombatBehaviorStep {
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

    // MARK: - Fleeing

    private mutating func enterFlee(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        enter(.fleeing)
        var step = unchanged()
        step.command = command(.flee(fleePoint(inputs)))
        return step
    }

    /// Running: ask for points further away until out of the fight, then hand back
    /// to the package. Recovering health does not bring the actor back.
    private mutating func advanceFleeing(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard inputs.distance < settings.fleeBreakDistance else { return endPursuit() }
        guard secondsSinceCommand >= settings.commandIntervalSeconds else { return unchanged() }
        var step = unchanged()
        step.command = command(.flee(fleePoint(inputs)))
        return step
    }

    /// A point to run to, turned by an angle drawn from the same generator the
    /// block roll uses so two actors fleeing one swing scatter.
    private mutating func fleePoint(_ inputs: CombatBehaviorInputs) -> SIMD3<Float> {
        // ±45 degrees.
        let turn = (Float(random.percent()) / 100 - 0.5) * (.pi / 2)
        return inputs.fleePoint(turnedBy: turn, settings: settings)
    }

    // MARK: - Searching and giving up

    /// Lost the target: go and look at the last place it was perceived.
    ///
    /// With no remembered position there is nothing to search — the level
    /// decayed to nothing before this step, which is 16.6's own rule that a
    /// stale investigate position can never be walked to — so the actor gives
    /// up outright rather than searching where it happens to be standing.
    private mutating func enterSearch(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard let position = inputs.awareness.lastKnownPosition else { return endPursuit() }
        searchCount += 1
        enter(.searching)
        var step = unchanged()
        step.startedSearch = true
        step.command = command(.investigate(position))
        return step
    }

    private mutating func advanceSearching(
        _ inputs: CombatBehaviorInputs
    ) -> CombatBehaviorStep {
        if inputs.awareness.isDetected || inputs.isForced {
            enter(.approaching)
            var step = unchanged()
            step.command = command(.approach(inputs.targetPosition))
            return step
        }
        guard phaseSeconds >= settings.searchSeconds else { return unchanged() }
        return endPursuit()
    }

    /// The fight is over for this actor: stop moving and hand it back to its
    /// 16.5 package. Hostility is untouched — the actor still has its quarrel,
    /// and re-engages the moment it perceives the target again.
    private mutating func endPursuit() -> CombatBehaviorStep {
        enter(.disengaged)
        var step = unchanged()
        step.endedPursuit = true
        step.command = command(.hold)
        return step
    }

    // MARK: - Bookkeeping

    private mutating func enter(_ next: CombatBehaviorPhase) {
        phase = next
        phaseSeconds = 0
    }

    /// Records that a command was issued this step and returns it, so the
    /// re-path interval is reset in exactly one place.
    private mutating func command(_ issued: CombatMovementCommand) -> CombatMovementCommand {
        secondsSinceCommand = 0
        return issued
    }

    private func unchanged() -> CombatBehaviorStep {
        CombatBehaviorStep(phase: phase)
    }
}
