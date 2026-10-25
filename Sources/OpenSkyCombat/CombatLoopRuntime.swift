// The fight as one object: hostility (`ActorCombatState`), one behavior machine
// per hostile actor (`CombatBehaviorMachine`), combat state derived from who is
// engaged (`CombatLoopState`), reactions, transient bounds
// (`CombatTransientLimits`), and the combat-music edge. All world access goes
// through `CombatLoopWorld`. See docs/engine/combat.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorldInterface
import simd

@MainActor
public final class CombatLoopRuntime: CombatControlling {
    /// Step the fight advances on, matching the actor-value runtime's and the
    /// perception pass's so a frame drives all three the same way. 1/60 s.
    public static let fixedStepSeconds: Float = 1.0 / 60

    /// Most whole steps one `advance(by:)` runs, so a multi-second stall cannot
    /// spend a minute of fighting in a single frame. Same cap, same reason as
    /// `ActorValueRuntime.maximumStepsPerAdvance`.
    public static let maximumStepsPerAdvance = 8

    /// Most actors that may hold a behavior machine at once. Equal to
    /// `ActorMovementLimits.maximumSimultaneousMovers`, because each engaged actor
    /// needs a mover. Past the cap the nearest win, and `crowdedOutCount` counts
    /// the rest.
    public static let maximumEngagedActors = ActorMovementLimits.maximumSimultaneousMovers

    /// How many incoming hits the trace keeps.
    public static let traceLimit = 16

    /// Seconds the player's damage flash decays over. An OpenSky number: the
    /// HUD hook needs a duration and no record states one.
    public static let damageFlashSeconds: Float = 0.35

    public let settings: CombatSettings
    /// Ceilings on everything the fight spawns.
    public var limits = CombatTransientLimits.standard
    /// The cadence, block, flee and search numbers every machine runs on.
    public var behaviorSettings = CombatBehaviorSettings.standard
    /// The Block experience of a blow the player blocks.
    public var skillUses = MeleeSkillUseSettings.vanilla
    /// Stagger strength and chance of an NPC blow.
    public var staggers = StaggerSettings.vanilla
    /// Flee distances and the ally follow radius.
    public var combatAI = CombatAISettings.vanilla
    /// Whether the advance, range, healing, shout, and flight settings reach the machines.
    /// Off keeps OpenSky's own numbers, which the older behaviour tests pin.
    public var applyingGameSettings = false
    /// Seeded, so a fight replays; drawn from only for the `iStaggerAttackChance` roll.
    var staggerRandom = ConditionRandom()

    public private(set) var state = CombatLoopState.calm
    /// One machine per actor that is fighting or has fought, keyed by actor.
    public private(set) var behaviors: [ReferenceKey: CombatBehaviorMachine] = [:]
    /// Hostile living actors the cap refused a machine at the last step.
    public private(set) var crowdedOutCount = 0
    /// Blows the player has taken, oldest first.
    public private(set) var incomingTrace: [CombatIncomingHit] = []
    public private(set) var incomingHitCount = 0
    /// The HUD's damage-flash hook: 1 the step a blow lands, decaying to 0 over
    /// `damageFlashSeconds`.
    public private(set) var playerDamageFlash: Float = 0
    /// Transients removed by the caps since construction, cumulative.
    public private(set) var trimmedTransients = CombatTransientCounts()
    /// Human-readable result of the last readout or script action.
    public var lastAction = CombatLoopOutcome.idle

    private(set) weak var world: (any CombatLoopWorld)?
    private var accumulator: Double = 0
    /// Targets `StartCombat` named, which engage without waiting to perceive
    /// anything and stay engaged while they cannot.
    private var forcedTargets: [ReferenceKey: ReferenceKey] = [:]
    /// Actors the player has struck that have not turned around yet. Cleared as
    /// soon as the machine is engaged, so a blow is a one-off shove into the
    /// fight rather than a standing override.
    private var provoked: Set<ReferenceKey> = []
    /// Combat state at the previous step, so music switches on the edge rather
    /// than being re-selected every step.
    private var wasInCombat = false
    /// Actors that fight for a commander, keyed by actor. See `CombatAllyRule`.
    public internal(set) var commanders: [ReferenceKey: ReferenceKey] = [:]
    /// Who each engaged actor fought at the last step.
    public internal(set) var targets: [ReferenceKey: ReferenceKey] = [:]
    /// Allies walking back to their commander, with the point each walks to.
    public internal(set) var following: [ReferenceKey: SIMD3<Float>] = [:]

    public init(settings: CombatSettings, world: (any CombatLoopWorld)? = nil) {
        self.settings = settings
        self.world = world
    }

    // MARK: - Hostility

    /// `key`'s stored regard for the player.
    public func hostility(of key: ReferenceKey) -> ActorHostility {
        world?.combatHostility(of: key) ?? .neutral
    }

    /// Sets `key`'s regard for the player outright, which is what the readout
    /// toggle does.
    ///
    /// - Returns: true when stored state changed.
    @discardableResult
    public func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        guard let world else { return false }
        let changed = world.setCombatHostility(hostility, on: key)
        if hostility == .neutral {
            endFight(of: key, world: world)
        }
        return changed
    }

    /// Makes `key` hostile because the player hurt it. Idempotent, so every hit path
    /// can call it.
    /// - Returns: true when this call turned the actor hostile.
    @discardableResult
    public func provoke(_ key: ReferenceKey) -> Bool {
        guard key != .player, hostility(of: key) != .hostile else { return false }
        return setHostility(.hostile, on: key)
    }

    /// `actor` joins `ally`'s fight against the player, as Assistance asks: it turns
    /// hostile and engages without first having to see the player.
    func joinFight(_ actor: ReferenceKey, assisting ally: ReferenceKey) {
        guard provoke(actor) else { return }
        provoked.insert(actor)
        record(.assisted(actor, ally: ally))
    }

    /// Interrupts `key`'s attack and plays its stagger clip.
    ///
    /// A charge in the actor's hand goes with the attack: the same blow that
    /// takes a swing away takes a cast away, which is why `isAttacking` counts
    /// the casting phase.
    public func noteStagger(of key: ReferenceKey) {
        var machine = behaviors[key] ?? makeMachine(for: key)
        if machine.pendingCast != nil {
            world?.cancelCombatCast(by: key)
        }
        guard machine.stagger() else { return }
        behaviors[key] = machine
        world?.playCombatClip(.stagger, on: key)
    }

    // MARK: - Reading

    /// Where `key` is in a fight, or nil when it has no machine.
    public func phase(of key: ReferenceKey) -> CombatBehaviorPhase? {
        behaviors[key]?.phase
    }

    /// What `key` is blocking with, or nil when its guard is down. The answer
    /// `combatBlock(of:)` gives for every actor that is not the player.
    public func blockKind(of key: ReferenceKey) -> MeleeBlockKind? {
        behaviors[key]?.blockKind
    }

    /// `key`'s combat state as `GetCombatState` and `IsInCombat` read it.
    /// Every fight is against the player, so it fights while any actor is engaged.
    public var isPlayerInCombat: Bool {
        behaviors.values.contains { $0.phase.isEngaged }
    }

    /// The player has no machine: every fight is against the player, so it fights while
    /// any actor fights, and searches while the engaged ones only search.
    public func activity(of key: ReferenceKey) -> ActorCombatActivity {
        guard key == .player else {
            guard let phase = behaviors[key]?.phase, phase.isEngaged else { return .notFighting }
            return phase == .searching ? .searching : .fighting
        }
        let engaged = behaviors.values.lazy.map(\.phase).filter(\.isEngaged)
        if engaged.contains(where: { $0 != .searching }) {
            return .fighting
        }
        return engaged.isEmpty ? .notFighting : .searching
    }

    /// The player targets the actor the loop picked. Another actor targets whom it
    /// fought at the last step: the player, or an ally of the player.
    public func combatTarget(of key: ReferenceKey) -> ReferenceKey? {
        guard activity(of: key) != .notFighting else { return nil }
        return key == .player ? state.target : targets[key] ?? .player
    }

    /// Whether `key` engages without having to perceive its target: a script
    /// called `StartCombat`, the player hit it and it has not detected the player yet,
    /// or it is an ally sent at its commander's foe.
    public func engagesWithoutPerceiving(_ key: ReferenceKey) -> Bool {
        forcedTargets[key] != nil || provoked.contains(key) || commanders[key] != nil
    }

    /// Whether a script named the player as `key`'s target.
    func isForcedOntoPlayer(_ key: ReferenceKey) -> Bool {
        forcedTargets[key] != nil
    }

    // MARK: - Frames

    /// Advances the fight by a wall delta, running whole fixed steps only. A zero,
    /// negative, or non-finite delta runs nothing, so a paused menu is safe.
    /// - Returns: how many whole steps ran.
    @discardableResult
    public func advance(by delta: Float) -> Int {
        guard delta.isFinite, delta > 0 else { return 0 }
        accumulator += Double(delta)
        var steps = 0
        while accumulator >= Double(Self.fixedStepSeconds), steps < Self.maximumStepsPerAdvance {
            accumulator -= Double(Self.fixedStepSeconds)
            step()
            steps += 1
        }
        accumulator = min(
            accumulator,
            Double(Self.fixedStepSeconds) * Double(Self.maximumStepsPerAdvance)
        )
        return steps
    }

    // MARK: - Persistence

    /// Drops what a reload cannot reproduce: arrows in flight, falling corpses, and
    /// every machine's phase. Hostility and actor values stay; the save holds them.
    /// Called on both sides of a save.
    public func prepareForPersistence() {
        world?.despawnCombatTransients()
        for key in behaviors.keys.sorted() {
            if behaviors[key]?.pendingCast != nil {
                world?.cancelCombatCast(by: key)
            }
            behaviors[key]?.park()
        }
        playerDamageFlash = 0
        accumulator = 0
    }

    // MARK: - Internal, for the satellite

    /// Advances one actor's machine by exactly one fixed step, creating it the
    /// first time that actor fights.
    ///
    /// Here rather than in the satellite because `behaviors` is `private(set)`
    /// and that is per file: the satellite decides what to tell a machine but
    /// must not be able to rewrite its phase behind the runtime's back.
    public func stepBehavior(
        of key: ReferenceKey, inputs: CombatBehaviorInputs
    ) -> CombatBehaviorStep {
        var machine = behaviors[key] ?? makeMachine(for: key)
        let step = machine.step(seconds: Self.fixedStepSeconds, inputs: inputs)
        behaviors[key] = machine
        if machine.isEngaged, inputs.awareness.isDetected {
            provoked.remove(key)
        }
        return step
    }

    /// A new machine for `key`, with its combat style folded into the settings.
    public func makeMachine(for key: ReferenceKey) -> CombatBehaviorMachine {
        let tuning = styleTuning(of: key)
        let tuned = behaviorSettings.tuned(by: tuning)
        return CombatBehaviorMachine(
            settings: combatAI.applyingFlee(
                to: applyingGameSettings ? combatAI
                    .applyingRanges(to: tuned, tuning: tuning) : tuned,
                interior: world?.combatInInterior ?? false
            ),
            seed: CombatBehaviorMachine.seed(for: key)
        )
    }

    /// `key`'s resolved combat style, or nil when it has none.
    public func styleTuning(of key: ReferenceKey) -> CombatStyleTuning? {
        world?.combatStyle(of: key)
    }

    /// Parks one machine without losing its counts, for an actor that died or
    /// whose cell unloaded. A charge in flight is dropped with it.
    public func parkBehavior(of key: ReferenceKey) {
        if behaviors[key]?.pendingCast != nil {
            world?.cancelCombatCast(by: key)
        }
        behaviors[key]?.park()
    }

    /// Drops a charge the world refused to begin, leaving the fight running.
    public func abandonCast(of key: ReferenceKey, world: any CombatLoopWorld) {
        world.cancelCombatCast(by: key)
        behaviors[key]?.abandonCast()
    }

    /// Forgets one machine outright, for an actor that is no longer resident.
    public func retireBehavior(of key: ReferenceKey) {
        behaviors.removeValue(forKey: key)
        forcedTargets.removeValue(forKey: key)
        provoked.remove(key)
        targets.removeValue(forKey: key)
        following.removeValue(forKey: key)
    }

    /// Records how many hostile living actors the engagement cap refused.
    public func noteCrowdedOut(_ count: Int) {
        crowdedOutCount = count
    }

    /// Appends one incoming hit to the trace, trimming to the limit.
    public func append(_ hit: CombatIncomingHit) {
        incomingHitCount += 1
        incomingTrace.append(hit)
        if incomingTrace.count > Self.traceLimit {
            incomingTrace.removeFirst(incomingTrace.count - Self.traceLimit)
        }
        playerDamageFlash = 1
    }

    public func record(_ outcome: CombatLoopOutcome) {
        lastAction = outcome
    }

    // MARK: - Private

    /// Ends one actor's fight: parks its machine, stops it walking, drops any
    /// script override, and hands it back to its package.
    private func endFight(of key: ReferenceKey, world: any CombatLoopWorld) {
        forcedTargets.removeValue(forKey: key)
        provoked.remove(key)
        guard behaviors[key] != nil else { return }
        if behaviors[key]?.pendingCast != nil {
            world.cancelCombatCast(by: key)
        }
        behaviors[key]?.park()
        world.stopCombatMovement(of: key)
        world.resumeCombatPackage(for: key)
    }

    /// One fixed step: every engaged actor acts, the state is re-derived, music
    /// follows the edge, the flash decays, and the caps are enforced.
    private func step() {
        guard let world else { return }
        let hostility = driveBehaviors(world: world)
        state = CombatLoopState.derive(
            actors: world.combatActors(),
            hostility: { [weak world] key in
                hostility[key] ?? world?.combatHostility(of: key) ?? .neutral
            },
            phase: { [weak self] key in self?.behaviors[key]?.phase },
            playerFeet: world.combatPlayer.feet
        )
        if state.isPlayerInCombat != wasInCombat {
            wasInCombat = state.isPlayerInCombat
            world.setCombatMusicActive(state.isPlayerInCombat)
        }
        playerDamageFlash = max(
            0, playerDamageFlash - Self.fixedStepSeconds / Self.damageFlashSeconds
        )
        enforceLimits(world: world)
    }

    private func enforceLimits(world: any CombatLoopWorld) {
        guard limits.needsTrim(world.combatTransients) else { return }
        let removed = world.trimCombatTransients(to: limits)
        trimmedTransients = CombatTransientCounts(
            liveProjectiles: trimmedTransients.liveProjectiles + removed.liveProjectiles,
            stuckProjectiles: trimmedTransients.stuckProjectiles + removed.stuckProjectiles,
            activeRagdolls: trimmedTransients.activeRagdolls + removed.activeRagdolls,
            awakeBodies: trimmedTransients.awakeBodies + removed.awakeBodies
        )
    }
}

extension CombatLoopRuntime {
    // MARK: - Script control (scope point 6)

    /// `StartCombat`: makes `actor` fight `target` at once.
    /// - Returns: true when the actor is now fighting. False for the player as the
    ///   aggressor, an untracked actor, or a target other than the player.
    @discardableResult
    public func startCombat(_ actor: ReferenceKey, with target: ReferenceKey) -> Bool {
        guard let world, actor != .player, target == .player else { return false }
        guard world.combatActor(key: actor)?.isDead == false else { return false }
        forcedTargets[actor] = target
        setHostility(.hostile, on: actor)
        record(.scriptStarted(actor))
        return true
    }

    /// `StopCombat`: ends `actor`'s fight and hands it back to its package,
    /// leaving its stored hostility alone — the wiki's `StopCombat` stops the
    /// fighting, and `SetRelationshipRank` is what changes how somebody feels.
    ///
    /// - Returns: true when there was a fight to stop.
    @discardableResult
    public func stopCombat(_ actor: ReferenceKey) -> Bool {
        guard let world, behaviors[actor]?.isEngaged == true else {
            forcedTargets.removeValue(forKey: actor)
            return false
        }
        endFight(of: actor, world: world)
        record(.scriptStopped(actor))
        return true
    }
}

extension CombatLoopRuntime {
    /// Every landed melee hit the player's swing produced: provokes each target and
    /// puts it in the fight. A hit that staggered also interrupts what it was doing.
    public func notePlayerHits(_ targets: [ReferenceKey], staggered: Set<ReferenceKey> = []) {
        for target in targets where target != .player && commanders[target] != .player {
            provoke(target)
            provoked.insert(target)
            if staggered.contains(target) {
                noteStagger(of: target)
            }
        }
    }

    /// The `iStaggerAttackChance` roll for a hit with no magnitude of its own, an arrow.
    public func rollsStagger() -> Bool {
        staggerRandom.percent() < staggers.attackChance
    }
}
