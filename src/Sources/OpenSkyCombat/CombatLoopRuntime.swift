// The fight as one object: hostility (`ActorCombatState`), one behavior machine
// per hostile actor (`CombatBehaviorMachine`), combat state derived from who is
// engaged (`CombatLoopState`), reactions, transient bounds
// (`CombatTransientLimits`), and the combat-music edge. All world access goes
// through `CombatLoopWorld`. See docs/engine/combat.md.

import Foundation
public import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyConditions
public import OpenSkyFormatsESM
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
    static let maximumEngagedActors = ActorMovementLimits.maximumSimultaneousMovers

    /// How many incoming hits the trace keeps.
    static let traceLimit = 16

    /// Seconds the player's damage flash decays over. An OpenSky number: the
    /// HUD hook needs a duration and no record states one.
    static let damageFlashSeconds: Float = 0.35

    public let settings: CombatSettings
    /// Ceilings on everything the fight spawns.
    var limits = CombatTransientLimits.standard
    /// The cadence, block, flee and search numbers every machine runs on.
    public var behaviorSettings = CombatBehaviorSettings.standard
    /// The Block experience of a blow the player blocks.
    var skillUses = MeleeSkillUseSettings.vanilla
    /// Stagger strength and chance of an NPC blow.
    public var staggers = StaggerSettings.vanilla
    /// The player's blows on friends and allies, which turn hostile only past a count.
    var friendlyFire = FriendlyFire()
    /// Seconds of fixed steps run, the friendly fire clock.
    private(set) var stepSeconds: Double = 0
    /// Flee distances and the ally follow radius.
    public var combatAI = CombatAISettings.vanilla
    /// Whether the advance, range, healing, shout, and flight settings reach the machines.
    /// Off keeps OpenSky's own numbers, which the older behaviour tests pin.
    public var applyingGameSettings = false
    /// Seeded, so a fight replays; drawn from only for the `iStaggerAttackChance` roll.
    var staggerRandom = ConditionRandom()
    /// The `fCombatDodge*` numbers a fighter sidesteps a threat by.
    public var danger = DangerSettings.vanilla
    /// Seeded like the stagger roll; drawn from for the sample time, the chance, and the side.
    var dangerRandom = ConditionRandom(seed: 0xD0D6_E000)
    /// Attackers whose blocked blow made them recoil, until their machine leaves the phase.
    var recoilers: Set<ReferenceKey> = []

    /// True while `key` plays the recoil of a blocked blow.
    func isRecoiling(_ key: ReferenceKey) -> Bool {
        recoilers.contains(key) && behaviors[key]?.phase == .staggered
    }

    /// Each fighter's watch on the threat list.
    public internal(set) var dangerWatches: [ReferenceKey: CombatDangerWatch] = [:]
    /// Each target's feet at the last two steps, for an archer's lead.
    var targetTracks: [ReferenceKey: TargetTrack] = [:]

    public private(set) var state = CombatLoopState.calm
    /// One machine per actor that is fighting or has fought, keyed by actor.
    public private(set) var behaviors: [ReferenceKey: CombatBehaviorMachine] = [:]
    /// Hostile living actors the cap refused a machine at the last step.
    private(set) var crowdedOutCount = 0
    /// Blows the player has taken, oldest first.
    private(set) var incomingTrace: [CombatIncomingHit] = []
    private(set) var incomingHitCount = 0
    /// The HUD's damage-flash hook: 1 the step a blow lands, decaying to 0 over
    /// `damageFlashSeconds`.
    public private(set) var playerDamageFlash: Float = 0
    /// Transients removed by the caps since construction, cumulative.
    private(set) var trimmedTransients = CombatTransientCounts()
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
    /// The hand of each actor's swing in progress, and how many swings it started.
    public internal(set) var strikes: [ReferenceKey: NPCStrikes] = [:]
    /// The NPCs whose killing swing started out of reach, with the target each closes on.
    /// A kill move can still start until the swing's wind-up ends.
    public internal(set) var killMoveSeekers: [ReferenceKey: ReferenceKey] = [:]
    /// The attack each NPC's pick chose for its swing in progress.
    public internal(set) var pickedAttacks: [ReferenceKey: NPCAttack] = [:]
    /// When each NPC last started each attack event, lowercased, on the step clock.
    var attackUses: [ReferenceKey: [String: Double]] = [:]
    /// The NPCs that keep facing their target through a melee attack.
    public internal(set) var attackTracks: [ReferenceKey: CombatAttackTrack] = [:]
    /// Allies walking back to their commander, with the point each walks to.
    public internal(set) var following: [ReferenceKey: SIMD3<Float>] = [:]
    /// The actors that warn the player by their aggro radius.
    public internal(set) var aggroWatches: [ReferenceKey: AggroWatch] = [:]
    /// The draw state of each NPC whose weapon is not away.
    public internal(set) var weaponDraws: [ReferenceKey: NPCWeaponDraw] = [:]
    /// NPC pairs whose observer attacks its target on sight, from the last foe scan.
    public internal(set) var foePairs: Set<CombatFoePair> = []
    /// NPC pairs an aggro radius turned into a fight: the observer attacks its target.
    var aggroFoePairs: Set<CombatFoePair> = []
    /// The pairs each NPC's own detection pass found, by observer.
    var scannedFoes: [ReferenceKey: Set<CombatFoePair>] = [:]
    /// Seconds until each NPC's next detection pass.
    var foeScanWaits: [ReferenceKey: Float] = [:]
    var foeScanRandom = ConditionRandom(seed: 0xF0E5_CA11)
    /// Each fighting NPC's target pick: the target and the seconds until it picks again.
    var targetPicks: [ReferenceKey: CombatTargetPick] = [:]
    /// Actors that fight an NPC that fights them, this step. They engage unseen.
    var retaliating: Set<ReferenceKey> = []
    /// Calm actors that joined an ally's fight against an NPC, with that NPC.
    var npcAssists: [ReferenceKey: ReferenceKey] = [:]
    /// Each calm actor beside an ally in a fight, which perception tracks so the actor
    /// helps only an ally it detects.
    public internal(set) var allyWatchPairs: Set<CombatFoePair> = []
    /// The actors that started the fight they are in.
    public internal(set) var aggressors: Set<ReferenceKey> = []
    /// Actors whose mark this fight was decided. A swing parks the machine, so a fighter
    /// re-enters combat many times in one fight.
    var markJudged: Set<ReferenceKey> = []
    /// Actors that joined an ally's fight, with that ally, until they enter combat.
    var joinedGroups: [ReferenceKey: ReferenceKey] = [:]

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
            FightSteps(owner: self).endFight(of: key, world: world)
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

    // MARK: - Reading

    /// Where `key` is in a fight, or nil when it has no machine.
    public func phase(of key: ReferenceKey) -> CombatBehaviorPhase? {
        behaviors[key]?.phase
    }

    /// What `key`'s combat mind is doing, as the condition functions read it.
    public func actionFacts(of key: ReferenceKey) -> ActorActionFacts? {
        behaviors[key]?.actionFacts
    }

    /// What `key` is blocking with, or nil when its guard is down. The answer
    /// `combatBlock(of:)` gives for every actor that is not the player.
    public func blockKind(of key: ReferenceKey) -> MeleeBlockKind? {
        behaviors[key]?.blockKind
    }

    /// The player's combat state as `GetCombatState` and `IsInCombat` read it: it fights
    /// while an actor fights it or its allies.
    public var isPlayerInCombat: Bool {
        behaviors.contains { $0.value.phase.isEngaged && fightsPlayerSide($0.key) }
    }

    /// The player has no machine: it fights while an actor fights it or its allies, and
    /// searches while those actors only search.
    public func activity(of key: ReferenceKey) -> ActorCombatActivity {
        guard key == .player else {
            guard let phase = behaviors[key]?.phase, phase.isEngaged else { return .notFighting }
            return phase == .searching ? .searching : .fighting
        }
        let engaged = behaviors.lazy.filter { self.fightsPlayerSide($0.key) }
            .map(\.value.phase).filter(\.isEngaged)
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

    /// Whether `key` fights from range: with a bow, a crossbow, a staff, or a spell.
    public func fightsRanged(_ key: ReferenceKey) -> Bool {
        FightSteps(owner: self).fightsRanged(key)
    }

    /// Whether `key` engages without having to perceive its target: a script
    /// called `StartCombat`, the player hit it and it has not detected the player yet,
    /// it is an ally sent at its commander's foe, or it fights back an NPC that attacks it.
    func engagesWithoutPerceiving(_ key: ReferenceKey) -> Bool {
        forcedTargets[key] != nil || provoked.contains(key) || commanders[key] != nil
            || retaliating.contains(key)
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
    func stepBehavior(
        of key: ReferenceKey, inputs: CombatBehaviorInputs
    ) -> CombatBehaviorStep {
        FightSteps(owner: self).stepBehavior(of: key, inputs: inputs)
    }

    /// A new machine for `key`, with its combat style folded into the settings.
    public func makeMachine(for key: ReferenceKey) -> CombatBehaviorMachine {
        let tuning = styleTuning(of: key)
        var tuned = behaviorSettings.tuned(by: tuning)
        if world?.combatWearsShield(key) == false {
            tuned.blockChance *= max(0, combatAI.blockChanceWeaponMult)
        }
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
    func abandonCast(of key: ReferenceKey, world: any CombatLoopWorld) {
        world.cancelCombatCast(by: key)
        behaviors[key]?.abandonCast()
    }

    /// Forgets one machine outright, for an actor that is no longer resident.
    public func retireBehavior(of key: ReferenceKey) {
        behaviors.removeValue(forKey: key)
        killMoveSeekers.removeValue(forKey: key)
        forcedTargets.removeValue(forKey: key)
        provoked.remove(key)
        targets.removeValue(forKey: key)
        strikes.removeValue(forKey: key)
        attackTracks.removeValue(forKey: key)
        dangerWatches.removeValue(forKey: key)
        recoilers.remove(key)
        following.removeValue(forKey: key)
        forgetMark(of: key)
    }

    public func record(_ outcome: CombatLoopOutcome) {
        lastAction = outcome
    }

    // MARK: - Private

    /// One fixed step: every engaged actor acts, the state is re-derived, music
    /// follows the edge, the flash decays, and the caps are enforced.
    private func step() {
        guard let world else { return }
        stepSeconds += Double(Self.fixedStepSeconds)
        let hostility = driveBehaviors(world: world)
        stepWeaponDraws(world: world)
        state = CombatLoopState.derive(
            actors: world.combatActors(),
            hostility: { [weak world] key in
                hostility[key] ?? world?.combatHostility(of: key) ?? .neutral
            },
            phase: { [weak self] key in
                guard let self, fightsPlayerSide(key) else { return nil }
                return behaviors[key]?.phase
            },
            playerFeet: world.combatPlayer.feet
        )
        if state.isPlayerInCombat != wasInCombat {
            wasInCombat = state.isPlayerInCombat
            world.setCombatMusicActive(state.isPlayerInCombat)
        }
        playerDamageFlash = max(
            0, playerDamageFlash - Self.fixedStepSeconds / Self.damageFlashSeconds
        )
        FightSteps(owner: self).enforceLimits(world: world)
    }
}

extension CombatLoopRuntime {
    // MARK: - Script control (scope point 6)

    /// `StartCombat`: makes `actor` fight `target` at once.
    /// - Returns: true when the actor is now fighting. False for the player as the
    ///   aggressor, an untracked actor, or a target other than the player.
    @discardableResult
    public func startCombat(_ actor: ReferenceKey, with target: ReferenceKey) -> Bool {
        guard
            let world, actor != .player, target == .player,
            world.combatActor(key: actor)?.isDead == false else { return false }
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
        FightSteps(owner: self).endFight(of: actor, world: world)
        record(.scriptStopped(actor))
        return true
    }
}

extension CombatLoopRuntime {
    /// Every landed melee hit the player's swing produced: provokes each target and
    /// puts it in the fight. A hit that staggered also interrupts what it was doing.
    public func notePlayerHits(_ targets: [ReferenceKey], staggered: Set<ReferenceKey> = []) {
        for target in targets where target != .player && commanders[target] != .player {
            guard FightSteps(owner: self).turnsOnPlayer(target) else { continue }
            provoke(target)
            provoked.insert(target)
            if staggered.contains(target) {
                noteStagger(of: target)
            }
        }
    }
}

extension CombatLoopRuntime {
    /// Records how many hostile living actors the engagement cap refused.
    func noteCrowdedOut(_ count: Int) {
        crowdedOutCount = count
    }

    /// Appends one incoming hit to the trace, trimming to the limit.
    func append(_ hit: CombatIncomingHit) {
        incomingHitCount += 1
        incomingTrace.append(hit)
        if incomingTrace.count > Self.traceLimit {
            incomingTrace.removeFirst(incomingTrace.count - Self.traceLimit)
        }
        playerDamageFlash = 1
    }
}

extension CombatLoopRuntime {
    /// `actor` joins `ally`'s fight against the player, as Assistance asks: it turns
    /// hostile and engages without first having to see the player.
    func joinFight(_ actor: ReferenceKey, assisting ally: ReferenceKey) {
        guard provoke(actor) else { return }
        provoked.insert(actor)
        joinedGroups[actor] = ally
        record(.assisted(actor, ally: ally))
    }

    /// Interrupts `key`'s attack and plays its stagger clip.
    ///
    /// A charge in the actor's hand goes with the attack: the same blow that
    /// takes a swing away takes a cast away, which is why `isAttacking` counts
    /// the casting phase.
    public func noteStagger(of key: ReferenceKey) {
        FightSteps(owner: self).noteStagger(of: key)
    }
}

extension CombatLoopRuntime {
    /// Steps the behaviour machines and ends fights.
    struct FightSteps {
        let owner: CombatLoopRuntime

        func fightsRanged(_ key: ReferenceKey) -> Bool {
            guard let type = owner.world?.combatWeapon(of: key).handType else { return false }
            return type.isRanged || type == .staff || type == .spell
        }

        func stepBehavior(
            of key: ReferenceKey, inputs: CombatBehaviorInputs
        ) -> CombatBehaviorStep {
            var machine = owner.behaviors[key] ?? owner.makeMachine(for: key)
            let wasEngaged = machine.isEngaged
            let step = machine.step(seconds: CombatLoopRuntime.fixedStepSeconds, inputs: inputs)
            owner.behaviors[key] = machine
            if !wasEngaged, machine.isEngaged, let world = owner.world {
                owner.noteEnteredCombat(key, provoked: owner.provoked.contains(key), world: world)
            } else if wasEngaged, !machine.isEngaged {
                owner.forgetMark(of: key)
            }
            if machine.isEngaged, inputs.awareness.isDetected {
                owner.provoked.remove(key)
            }
            return step
        }

        /// Ends one actor's fight: parks its machine, stops it walking, drops any
        /// script override, and hands it back to its package.
        func endFight(of key: ReferenceKey, world: any CombatLoopWorld) {
            owner.forcedTargets.removeValue(forKey: key)
            owner.provoked.remove(key)
            owner.forgetMark(of: key)
            guard owner.behaviors[key] != nil else { return }
            if owner.behaviors[key]?.pendingCast != nil {
                world.cancelCombatCast(by: key)
            }
            owner.behaviors[key]?.park()
            world.stopCombatMovement(of: key)
            world.resumeCombatPackage(for: key)
        }

        func enforceLimits(world: any CombatLoopWorld) {
            guard owner.limits.needsTrim(world.combatTransients) else { return }
            let removed = world.trimCombatTransients(to: owner.limits)
            owner.trimmedTransients = CombatTransientCounts(
                liveProjectiles: owner.trimmedTransients.liveProjectiles + removed.liveProjectiles,
                stuckProjectiles: owner.trimmedTransients.stuckProjectiles + removed
                    .stuckProjectiles,
                activeRagdolls: owner.trimmedTransients.activeRagdolls + removed.activeRagdolls,
                awakeBodies: owner.trimmedTransients.awakeBodies + removed.awakeBodies
            )
        }

        /// False while a friend or an ally takes the blow without fighting back.
        func turnsOnPlayer(_ target: ReferenceKey) -> Bool {
            guard owner.hostility(of: target) != .hostile else { return true }
            return owner.friendlyFire.noteHit(
                on: target,
                reaction: owner.world?.combatReaction(toPlayerOf: target),
                inCombat: owner.behaviors[target]?.phase.isEngaged == true,
                now: owner.stepSeconds
            )
        }

        func noteStagger(of key: ReferenceKey) {
            var machine = owner.behaviors[key] ?? owner.makeMachine(for: key)
            if machine.pendingCast != nil {
                owner.world?.cancelCombatCast(by: key)
            }
            guard machine.stagger() else { return }
            owner.behaviors[key] = machine
            owner.world?.playCombatClip(.stagger, on: key)
        }
    }
}
