// One actor's combat mind (issue #424, roadmap item 16.7, scope points 1
// through 5), as a pure value over a fixed step.
//
// This is what replaces `DevTargetDriver`. The clock attacked on an interval
// from wherever it stood, at whatever was in front of it, and never gave up.
// The machine below decides, in this order every step: is my target still
// there, am I hurt enough to run, can I still see it, am I close enough to
// swing. Everything downstream of a decision — the 15.4 hit volume, the 15.4
// damage formula, the actor values, the death and the ragdoll — is untouched,
// which is the whole point of having built the clock through the shipping paths.
//
// ## Fixed step, no clock, no sampling
//
// `step(seconds:inputs:)` is a pure function of the previous state, the inputs
// and the elapsed seconds, exactly as `DetectionPairState.advanced` is. It
// never reads a clock. The one place a decision is not determined by its inputs
// is the block roll, and that draws from a `ConditionRandom` seeded per actor
// from its `ReferenceKey` — the same splitmix generator the condition system's
// `GetRandomPercent` uses, seeded the same way. So a fight replays exactly, and
// two actors in one room still do not block in lockstep.
//
// ## Why the machine asks for movement instead of performing it
//
// It emits a `CombatMovementCommand` and the runtime hands it to 16.4's
// `MoveToPointControl`. The mover is the movement authority — it owns the
// capsule, the navmesh path, the stuck recovery and the persistence — and a
// combat layer that wrote positions would be a second one that disagreed with
// it. This is the same split 16.4 established for packages, and it is why
// fleeing is "ask for a point away from the target" rather than "walk backwards".
//
// Documented in docs/engine/combat.md.

import Foundation
import simd

/// The decision layer for one actor in one fight.
nonisolated struct CombatBehaviorMachine: Equatable, Sendable {
    let settings: CombatBehaviorSettings

    private(set) var phase = CombatBehaviorPhase.idle
    /// Seconds spent in the current phase.
    private(set) var phaseSeconds: Float = 0
    /// Fights entered, attacks started, contact steps reached, guards raised and
    /// searches begun since construction. The panel reads all five; the first
    /// two differ only by an attack a stagger interrupted before it connected.
    private(set) var fightCount = 0
    private(set) var attackCount = 0
    private(set) var contactCount = 0
    private(set) var blockCount = 0
    private(set) var searchCount = 0

    /// Seeded per actor, drawn from only for the block roll.
    private var random: ConditionRandom
    /// Seconds since the last movement command, so a chase re-paths on the
    /// stated interval rather than every step.
    private var secondsSinceCommand: Float = 0

    init(settings: CombatBehaviorSettings = .standard, seed: UInt64) {
        self.settings = settings
        random = ConditionRandom(seed: seed)
    }

    /// A stable per-actor seed.
    ///
    /// Folded from the key's own spelling rather than from `hashValue`, because
    /// Swift seeds `String` hashing per process: a `hashValue` seed would make
    /// two runs of the same fight differ, which is exactly what the determinism
    /// tests exist to catch.
    static func seed(for key: ReferenceKey) -> UInt64 {
        var state = ConditionRandom.defaultSeed
        for byte in key.description.utf8 {
            state = (state ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return state
    }

    /// Whether this actor counts as being in the fight.
    var isEngaged: Bool {
        phase.isEngaged
    }

    /// What this actor is blocking with, or nil when its guard is down.
    ///
    /// Always `.weapon`: an actor blocking with a shield needs the equipment
    /// resolution that would tell it apart from a raised sword, and reporting
    /// `.shield` without one would move the damage reduction to a different
    /// pinned constant on a guess. Stated in docs/engine/combat.md.
    var blockKind: MeleeBlockKind? {
        phase == .blocking ? .weapon : nil
    }

    /// Advances by exactly one fixed step and reports what it did.
    mutating func step(seconds: Float, inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard seconds > 0, seconds.isFinite else { return unchanged() }
        phaseSeconds += seconds
        secondsSinceCommand += seconds
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

    /// Interrupts whatever is in flight, exactly as the graph's own stagger
    /// transition takes the player's attack away.
    ///
    /// A fleeing or searching actor staggers too, and lands back in the gap
    /// between attacks: the next step re-reads its health and its awareness and
    /// sends it straight back to running or looking if that is still what those
    /// say. A blow interrupts whatever the actor was doing, and nothing is
    /// decided twice.
    ///
    /// An actor that was not fighting at all is in the fight afterwards. Being
    /// struck is being told where somebody is, and that is the *existing* combat
    /// entry — the player's own blow — rather than a second perception rule: the
    /// runtime keeps the actor engaged for the step it takes to turn around.
    ///
    /// - Returns: true when the machine actually entered a stagger, so a caller
    ///   asks for a clip only when there is one to play.
    @discardableResult
    mutating func stagger() -> Bool {
        guard phase != .staggered else { return false }
        if !phase.isEngaged {
            fightCount += 1
        }
        enter(.staggered)
        return true
    }

    /// Ends the fight outright without touching the counts, for `StopCombat`
    /// and for an actor whose cell unloaded.
    mutating func park() {
        enter(.idle)
        secondsSinceCommand = 0
    }

    // MARK: - Waiting

    /// Not in a fight: engage as soon as the target is perceived, or as soon as
    /// a script says to.
    ///
    /// This is scope point 5's single new combat entry, and it is deliberately
    /// the only one: hostility is still entered by the player's blow, the panel
    /// toggle or a script, and what widened is *when an actor already marked
    /// hostile starts fighting* — on perceiving the target rather than on being
    /// hit by it.
    ///
    /// An actor still under the flee threshold does not start a fight, which is
    /// what stops one it just ran from restarting the moment it looks back: it
    /// broke off because it was losing, and nothing here heals it.
    private mutating func advanceWaiting(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard !shouldFlee(inputs) else { return unchanged() }
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
        if shouldFlee(inputs) {
            return enterFlee(inputs)
        }
        if !inputs.awareness.isDetected, !inputs.isForced {
            return enterSearch(inputs)
        }
        switch phase {
        case .approaching: return advanceApproaching(inputs)
        case .spacing: return advanceSpacing(inputs)
        case .blocking: return advanceBlocking(inputs)
        case .windup: return advanceWindup()
        case .contact: return enterAndReport(.recovery)
        case .recovery:
            return phaseSeconds >= settings.recoverySeconds ? enterSpacing() : unchanged()
        default: return unchanged()
        }
    }

    private mutating func advanceApproaching(
        _ inputs: CombatBehaviorInputs
    ) -> CombatBehaviorStep {
        guard inputs.distance > strikingDistance(inputs) else { return enterSpacing() }
        guard secondsSinceCommand >= settings.commandIntervalSeconds else { return unchanged() }
        var step = unchanged()
        step.command = command(.approach(inputs.targetPosition))
        return step
    }

    private mutating func advanceSpacing(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard inputs.distance <= strikingDistance(inputs) else {
            enter(.approaching)
            var step = unchanged()
            step.command = command(.approach(inputs.targetPosition))
            return step
        }
        guard phaseSeconds >= settings.attackIntervalSeconds else { return unchanged() }
        return startAttack()
    }

    private mutating func advanceBlocking(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard phaseSeconds >= settings.blockSeconds else { return unchanged() }
        guard inputs.distance <= strikingDistance(inputs) else {
            enter(.approaching)
            var step = unchanged()
            step.command = command(.approach(inputs.targetPosition))
            return step
        }
        return startAttack()
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

    /// How close the actor wants to be before it swings: its own reach, less
    /// the stated margin, and never negative.
    private func strikingDistance(_ inputs: CombatBehaviorInputs) -> Float {
        max(0, inputs.reach - settings.reachSlack)
    }

    // MARK: - Fleeing

    private func shouldFlee(_ inputs: CombatBehaviorInputs) -> Bool {
        inputs.healthFraction.isFinite
            && inputs.healthFraction <= settings.fleeHealthFraction
    }

    private mutating func enterFlee(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        enter(.fleeing)
        var step = unchanged()
        step.command = command(.flee(fleePoint(inputs)))
        return step
    }

    /// Running: keep asking for a point further away until far enough from the
    /// target to be out of the fight, then hand back to the package.
    ///
    /// Health recovering above the threshold does not bring the actor back into
    /// the fight; nothing in this engine heals an NPC mid-fight, and an actor
    /// that turned and ran and then turned around again would be a decision the
    /// player cannot read.
    private mutating func advanceFleeing(_ inputs: CombatBehaviorInputs) -> CombatBehaviorStep {
        guard inputs.distance < settings.fleeBreakDistance else { return endPursuit() }
        guard secondsSinceCommand >= settings.commandIntervalSeconds else { return unchanged() }
        var step = unchanged()
        step.command = command(.flee(fleePoint(inputs)))
        return step
    }

    /// A point `fleeDistance` away from the target, along the line from the
    /// target through the actor and turned by a seeded angle.
    ///
    /// Turned rather than straight because a straight line runs into whatever is
    /// behind the actor and the mover would give up against it; a different
    /// angle per draw means the retry after a failed path is a different
    /// request. Two actors fleeing the same swing scatter, which is also what a
    /// player expects to see.
    private mutating func fleePoint(_ inputs: CombatBehaviorInputs) -> SIMD3<Float> {
        let offset = inputs.actorPosition - inputs.targetPosition
        let planar = SIMD2(offset.x, offset.y)
        let base = simd_length(planar) > 0 ? simd_normalize(planar) : SIMD2<Float>(1, 0)
        // ±45 degrees, drawn from the same generator the block roll uses.
        let turn = (Float(random.percent()) / 100 - 0.5) * (.pi / 2)
        let direction = SIMD2(
            base.x * cos(turn) - base.y * sin(turn),
            base.x * sin(turn) + base.y * cos(turn)
        )
        return inputs.actorPosition
            + SIMD3(direction.x, direction.y, 0) * settings.fleeDistance
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

    private mutating func enterAndReport(_ next: CombatBehaviorPhase) -> CombatBehaviorStep {
        enter(next)
        return unchanged()
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
