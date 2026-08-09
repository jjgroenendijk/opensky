// The fight, as one object (issues #374 and #424, roadmap items 15.7 and 16.7).
//
// Items 15.3 through 15.6 built the pieces: values that can be taken off, a
// swing that takes them, an arrow that flies, a corpse that falls and can be
// looted. Item 15.7 made those into a loop with a stand-in opponent — a clock
// that attacked on a fixed interval from wherever it stood. Item 16.7 deletes
// the clock and puts a mind in its place:
//
//   * hostility, one enum per actor, entered by the player's own blow, the panel
//     toggle or a script (`ActorCombatState`);
//   * a combat behavior machine per hostile actor (`CombatBehaviorMachine`),
//     which approaches through 16.4 movement, attacks through the shipping
//     windup-contact-recovery path, blocks, breaks off at low health, searches
//     the last place it perceived its target and gives up;
//   * combat state, derived every step from who is *engaged* rather than from
//     who is angry (`CombatLoopState`);
//   * reactions in both directions — the actor staggers, the player recoils;
//   * bounds on everything the fight spawns (`CombatTransientLimits`) and on how
//     many actors may fight at once;
//   * and the combat-music edge, which now falls the moment the last opponent
//     gives up rather than when it is finally killed.
//
// Main-actor, like the other directors, and advanced from the same paused-aware
// world delta the actor-value runtime, the perception pass and the ragdolls
// take. Everything it touches the world with goes through `CombatLoopWorld`, so
// the whole runtime is testable against a fake.
//
// Documented in docs/engine/combat.md.

import Foundation
import simd

@MainActor
final class CombatLoopRuntime {
    /// Step the fight advances on, matching the actor-value runtime's and the
    /// perception pass's so a frame drives all three the same way. 1/60 s.
    static let fixedStepSeconds: Float = 1.0 / 60

    /// Most whole steps one `advance(by:)` runs, so a multi-second stall cannot
    /// spend a minute of fighting in a single frame. Same cap, same reason as
    /// `ActorValueRuntime.maximumStepsPerAdvance`.
    static let maximumStepsPerAdvance = 8

    /// Most actors that may hold a behavior machine at once (scope point 7).
    ///
    /// Deliberately `NPCMovementRuntime.maximumSimultaneousMovers`: every
    /// engaged actor asks the mover for a path, so a ninth fighter would be one
    /// whose approach silently never started. Past the cap the nearest actors
    /// win and `crowdedOutCount` says how many did not, because a silent
    /// truncation would read as "nobody else was fighting".
    static let maximumEngagedActors = NPCMovementRuntime.maximumSimultaneousMovers

    /// How many incoming hits the trace keeps.
    static let traceLimit = 16

    /// Seconds the player's damage flash decays over. An OpenSky number: the
    /// HUD hook needs a duration and no record states one.
    static let damageFlashSeconds: Float = 0.35

    let settings: CombatSettings
    /// Ceilings on everything the fight spawns.
    var limits = CombatTransientLimits.standard
    /// The cadence, block, flee and search numbers every machine runs on.
    var behaviorSettings = CombatBehaviorSettings.standard

    private(set) var state = CombatLoopState.calm
    /// One machine per actor that is fighting or has fought, keyed by actor.
    private(set) var behaviors: [ReferenceKey: CombatBehaviorMachine] = [:]
    /// Hostile living actors the cap refused a machine at the last step.
    private(set) var crowdedOutCount = 0
    /// Blows the player has taken, oldest first.
    private(set) var incomingTrace: [CombatIncomingHit] = []
    private(set) var incomingHitCount = 0
    /// The HUD's damage-flash hook: 1 the step a blow lands, decaying to 0 over
    /// `damageFlashSeconds`.
    private(set) var playerDamageFlash: Float = 0
    /// Transients removed by the caps since construction, cumulative.
    private(set) var trimmedTransients = CombatTransientCounts()
    /// Human-readable result of the last panel or script action.
    var lastActionText = "No fight yet."

    private weak var world: (any CombatLoopWorld)?
    private var accumulator: Double = 0
    private var attackID = 0
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

    init(settings: CombatSettings, world: (any CombatLoopWorld)? = nil) {
        self.settings = settings
        self.world = world
    }

    /// Attaches (or detaches) the world the loop runs over.
    func attach(world: (any CombatLoopWorld)?) {
        self.world = world
        reset()
    }

    // MARK: - Hostility

    /// `key`'s stored regard for the player.
    func hostility(of key: ReferenceKey) -> ActorHostility {
        world?.combatHostility(of: key) ?? .neutral
    }

    /// Sets `key`'s regard for the player outright, which is what the panel
    /// toggle does.
    ///
    /// - Returns: true when stored state changed.
    @discardableResult
    func setHostility(_ hostility: ActorHostility, on key: ReferenceKey) -> Bool {
        guard let world else { return false }
        let changed = world.setCombatHostility(hostility, on: key)
        if hostility == .neutral {
            endFight(of: key, world: world)
        }
        return changed
    }

    /// Makes `key` hostile because the player hurt it, which is one of the three
    /// ways hostility is entered.
    ///
    /// Idempotent, so the several places a blow lands — a swing, an arrow, a
    /// script — can all call it without checking first.
    ///
    /// - Returns: true when this call is what turned the actor hostile.
    @discardableResult
    func provoke(_ key: ReferenceKey) -> Bool {
        guard key != .player, hostility(of: key) != .hostile else { return false }
        return setHostility(.hostile, on: key)
    }

    /// Every landed melee hit the player's swing produced: provokes each target,
    /// puts it in the fight, and interrupts whatever it was doing.
    func notePlayerHits(_ targets: [ReferenceKey]) {
        for target in targets where target != .player {
            provoke(target)
            provoked.insert(target)
            noteStagger(of: target)
        }
    }

    /// Interrupts `key`'s attack and plays its stagger clip.
    func noteStagger(of key: ReferenceKey) {
        var machine = behaviors[key] ?? CombatBehaviorMachine(
            settings: behaviorSettings, seed: CombatBehaviorMachine.seed(for: key)
        )
        guard machine.stagger() else { return }
        behaviors[key] = machine
        world?.playCombatClip(.stagger, on: key)
    }

    // MARK: - Script control (scope point 6)

    /// `StartCombat`: makes `actor` fight `target` at once, without waiting for
    /// it to perceive anything.
    ///
    /// - Returns: true when the actor is now fighting. False for the player as
    ///   the aggressor, for an actor this session does not track, and for a
    ///   target other than the player — the fight this engine runs is against
    ///   the player, so naming anybody else would be a fight nothing simulates.
    @discardableResult
    func startCombat(_ actor: ReferenceKey, with target: ReferenceKey) -> Bool {
        guard let world, actor != .player, target == .player else { return false }
        guard world.combatActors().contains(where: { $0.key == actor && !$0.isDead })
        else { return false }
        forcedTargets[actor] = target
        setHostility(.hostile, on: actor)
        record("Combat: a script started \(actor.description) fighting the player.")
        return true
    }

    /// `StopCombat`: ends `actor`'s fight and hands it back to its package,
    /// leaving its stored hostility alone — the wiki's `StopCombat` stops the
    /// fighting, and `SetRelationshipRank` is what changes how somebody feels.
    ///
    /// - Returns: true when there was a fight to stop.
    @discardableResult
    func stopCombat(_ actor: ReferenceKey) -> Bool {
        guard let world, behaviors[actor]?.isEngaged == true else {
            forcedTargets.removeValue(forKey: actor)
            return false
        }
        endFight(of: actor, world: world)
        record("Combat: a script stopped \(actor.description) fighting.")
        return true
    }

    // MARK: - Reading

    /// Where `key` is in a fight, or nil when it has no machine.
    func phase(of key: ReferenceKey) -> CombatBehaviorPhase? {
        behaviors[key]?.phase
    }

    /// What `key` is blocking with, or nil when its guard is down. The answer
    /// `combatBlock(of:)` gives for every actor that is not the player.
    func blockKind(of key: ReferenceKey) -> MeleeBlockKind? {
        behaviors[key]?.blockKind
    }

    /// `key`'s combat state as `GetCombatState` and `IsInCombat` read it.
    func activity(of key: ReferenceKey) -> ActorCombatActivity {
        guard let phase = behaviors[key]?.phase, phase.isEngaged else { return .notFighting }
        return phase == .searching ? .searching : .fighting
    }

    /// Who `key` is fighting, which is the player unless a script said
    /// otherwise.
    func target(of key: ReferenceKey) -> ReferenceKey {
        forcedTargets[key] ?? .player
    }

    /// Whether `key` engages without having to perceive its target: a script
    /// called `StartCombat`, or the player hit it and it has not turned around
    /// yet.
    func engagesWithoutPerceiving(_ key: ReferenceKey) -> Bool {
        forcedTargets[key] != nil || provoked.contains(key)
    }

    // MARK: - Frames

    /// Advances the fight by a wall delta, running whole fixed steps only.
    ///
    /// A zero delta advances nothing and is safe to call every frame — the
    /// established menu-pause rule, which reaches this layer as delta 0 exactly
    /// as it reaches the Papyrus VM and the actor-value runtime. A negative or
    /// non-finite delta is treated the same way rather than run backwards.
    ///
    /// - Returns: how many whole steps ran.
    @discardableResult
    func advance(by delta: Float) -> Int {
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

    /// Drops everything a reload cannot reproduce, which is what makes a fight
    /// saved mid-swing resume consistently. Called on both sides of a save.
    ///
    /// Hostility and actor values are untouched: those are components and the
    /// save carries them. What goes is the in-flight transients — arrows in the
    /// air, corpses still falling — and every machine's phase, which restarts
    /// from "not fighting" rather than resuming mid-windup. An actor that is
    /// still hostile and can still perceive the player re-engages on the first
    /// step after the load, which is the same route it took the first time.
    func prepareForPersistence() {
        world?.despawnCombatTransients()
        for key in behaviors.keys {
            behaviors[key]?.park()
        }
        playerDamageFlash = 0
        accumulator = 0
    }

    /// Forgets every live fight without touching stored hostility.
    func reset() {
        state = .calm
        behaviors = [:]
        forcedTargets = [:]
        provoked = []
        crowdedOutCount = 0
        incomingTrace = []
        incomingHitCount = 0
        playerDamageFlash = 0
        trimmedTransients = CombatTransientCounts()
        accumulator = 0
        attackID = 0
        wasInCombat = false
    }

    /// Empties the incoming trace and its count without disturbing the fight.
    func clearTrace() {
        incomingTrace = []
        incomingHitCount = 0
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
        var machine = behaviors[key] ?? CombatBehaviorMachine(
            settings: behaviorSettings, seed: CombatBehaviorMachine.seed(for: key)
        )
        let step = machine.step(seconds: Self.fixedStepSeconds, inputs: inputs)
        behaviors[key] = machine
        if machine.isEngaged {
            provoked.remove(key)
        }
        return step
    }

    /// Parks one machine without losing its counts, for an actor that died or
    /// whose cell unloaded.
    func parkBehavior(of key: ReferenceKey) {
        behaviors[key]?.park()
    }

    /// Forgets one machine outright, for an actor that is no longer resident.
    func retireBehavior(of key: ReferenceKey) {
        behaviors.removeValue(forKey: key)
        forcedTargets.removeValue(forKey: key)
        provoked.remove(key)
    }

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

    /// The next attack's identity, so two hits from one attack read as one.
    func nextAttackID() -> Int {
        attackID += 1
        return attackID
    }

    /// Stores and returns one panel-facing outcome line.
    @discardableResult
    func record(_ text: String) -> String {
        lastActionText = text
        return text
    }

    // MARK: - Private

    /// Ends one actor's fight: parks its machine, stops it walking, drops any
    /// script override, and hands it back to its package.
    private func endFight(of key: ReferenceKey, world: any CombatLoopWorld) {
        forcedTargets.removeValue(forKey: key)
        provoked.remove(key)
        guard behaviors[key] != nil else { return }
        behaviors[key]?.park()
        world.stopCombatMovement(of: key)
        world.resumeCombatPackage(for: key)
    }

    /// One fixed step: every engaged actor acts, the state is re-derived, music
    /// follows the edge, the flash decays, and the caps are enforced.
    private func step() {
        guard let world else { return }
        driveBehaviors(world: world)
        state = CombatLoopState.derive(
            actors: world.combatActors(),
            hostility: { [weak world] key in world?.combatHostility(of: key) ?? .neutral },
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

/// What one actor is doing about a fight, as `GetCombatState` spells it.
///
/// Three cases because the Creation Kit wiki documents three returns, and 16.7
/// is what makes the third reachable: an actor that lost its target and is
/// looking for it is neither out of combat nor fighting.
nonisolated enum ActorCombatActivity: UInt8, Equatable, Sendable, CaseIterable {
    /// Not fighting. `GetCombatState` 0.
    ///
    /// Spelled `notFighting` rather than `none`, because `.none` on an
    /// `Optional` of this type would mean "no answer" and read identically at
    /// every call site that chains through one.
    case notFighting = 0
    /// Fighting. `GetCombatState` 1.
    case fighting = 1
    /// Searching for a target it lost. `GetCombatState` 2.
    case searching = 2

    var displayName: String {
        switch self {
        case .notFighting: "not in combat"
        case .fighting: "in combat"
        case .searching: "searching"
        }
    }
}
