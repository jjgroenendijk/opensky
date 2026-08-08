// The fight, as one object (issue #374, roadmap item 15.7).
//
// Items 15.3 through 15.6 built the pieces: values that can be taken off, a
// swing that takes them, an arrow that flies, a corpse that falls and can be
// looted. Each of them is complete on its own and none of them makes a fight,
// because nothing decided who was fighting whom or hit back. This runtime is
// that decision layer, and it is deliberately the smallest one that produces a
// loop:
//
//   * hostility, one enum per actor, entered by the player's own blow or by the
//     panel toggle (`ActorCombatState`);
//   * combat state, derived every step from who is hostile and alive
//     (`CombatLoopState`);
//   * an opponent that attacks back on a clock (`DevTargetDriver`), through the
//     15.4 hit volume and the 15.4 damage formula;
//   * reactions in both directions — the target staggers, the player recoils;
//   * bounds on everything the fight spawns (`CombatTransientLimits`);
//   * and the combat-music edge the music page has been holding a seam for.
//
// What it is not is AI. There is no perception, no pathing, no faction and no
// crime; the opponent is a stand-in and `DevTargetDriver` says so at length.
// Everything downstream of "someone hit someone" is nevertheless the shipping
// path, so M16 replaces the clock and keeps the rest.
//
// Main-actor, like the other directors, and advanced from the same paused-aware
// world delta the actor-value runtime and the ragdolls take. Everything it
// touches the world with goes through `CombatLoopWorld`, so the whole runtime is
// testable against a fake.
//
// Documented in docs/engine/combat.md.

import Foundation
import simd

@MainActor
final class CombatLoopRuntime {
    /// Step the fight advances on, matching the actor-value runtime's so a
    /// frame drives regeneration and combat the same way. 1/60 s.
    static let fixedStepSeconds: Float = 1.0 / 60

    /// Most whole steps one `advance(by:)` runs, so a multi-second stall cannot
    /// spend a minute of fighting in a single frame. Same cap, same reason as
    /// `ActorValueRuntime.maximumStepsPerAdvance`.
    static let maximumStepsPerAdvance = 8

    /// How many incoming hits the trace keeps.
    static let traceLimit = 16

    /// Seconds the player's damage flash decays over. An OpenSky number: the
    /// HUD hook needs a duration and no record states one.
    static let damageFlashSeconds: Float = 0.35

    let settings: CombatSettings
    /// Ceilings on everything the fight spawns.
    var limits = CombatTransientLimits.standard
    /// The profile the dev target swings with. Written when its equipment
    /// resolves; the unarmed profile until then, which is a fight the player
    /// can survive long enough to watch.
    var devTargetWeapon = MeleeWeaponProfile.unarmed

    private(set) var state = CombatLoopState.calm
    private(set) var driver = DevTargetDriver()
    /// The designated opponent, or nil when none is spawned.
    private(set) var devTarget: ReferenceKey?
    /// Blows the player has taken, oldest first.
    private(set) var incomingTrace: [CombatIncomingHit] = []
    private(set) var incomingHitCount = 0
    /// The HUD's damage-flash hook: 1 the step a blow lands, decaying to 0 over
    /// `damageFlashSeconds`.
    private(set) var playerDamageFlash: Float = 0
    /// Transients removed by the caps since construction, cumulative.
    private(set) var trimmedTransients = CombatTransientCounts()
    /// Human-readable result of the last panel action.
    var lastActionText = "No fight yet."

    private weak var world: (any CombatLoopWorld)?
    private var accumulator: Double = 0
    private var attackID = 0
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
        if hostility == .neutral, key == devTarget {
            driver.park()
        }
        return changed
    }

    /// Makes `key` hostile because the player hurt it, which is the only way
    /// hostility is entered outside the panel.
    ///
    /// Idempotent, so the several places a blow lands — a swing, an arrow, a
    /// dev control — can all call it without checking first.
    ///
    /// - Returns: true when this call is what turned the actor hostile.
    @discardableResult
    func provoke(_ key: ReferenceKey) -> Bool {
        guard key != .player, hostility(of: key) != .hostile else { return false }
        return setHostility(.hostile, on: key)
    }

    /// Every landed melee hit the player's swing produced: provokes each target
    /// and interrupts the dev target's own attack when it was the one struck.
    func notePlayerHits(_ targets: [ReferenceKey]) {
        for target in targets {
            provoke(target)
            noteStagger(of: target)
        }
    }

    /// Interrupts `key`'s attack if it is the dev target, and plays its stagger
    /// clip.
    func noteStagger(of key: ReferenceKey) {
        guard key == devTarget, driver.stagger() else { return }
        world?.playCombatClip(.stagger, on: key)
    }

    // MARK: - The dev target

    /// Designates the nearest living actor as the opponent, turns it hostile
    /// and starts its attack clock.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func spawnDevTarget() -> String {
        guard let world else {
            return record("Dev target unavailable: no combat world attached.")
        }
        let player = world.combatPlayer.feet
        let candidates = world.combatActors().filter { !$0.isDead }
        guard
            let nearest = candidates.min(by: {
                (simd_distance($0.feet, player), $0.key)
                    < (simd_distance($1.feet, player), $1.key)
            })
        else {
            return record("Dev target unavailable: no living actor is resident.")
        }
        devTarget = nearest.key
        driver.reset()
        driver.isEnabled = true
        setHostility(.hostile, on: nearest.key)
        return record("Dev target: \(nearest.name) is now hostile and attacking.")
    }

    /// Stops the opponent's clock, calms it, and forgets it.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func resetDevTarget() -> String {
        guard let key = devTarget else {
            return record("Dev target: none was spawned.")
        }
        setHostility(.neutral, on: key)
        devTarget = nil
        driver.isEnabled = false
        driver.reset()
        return record("Dev target: cleared.")
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
    /// air, corpses still falling — and the opponent's attack phase, which
    /// restarts from the interval rather than resuming mid-windup.
    func prepareForPersistence() {
        world?.despawnCombatTransients()
        driver.park()
        playerDamageFlash = 0
        accumulator = 0
    }

    /// Forgets every live fight without touching stored hostility.
    func reset() {
        state = .calm
        driver = DevTargetDriver()
        devTarget = nil
        incomingTrace = []
        incomingHitCount = 0
        playerDamageFlash = 0
        trimmedTransients = .none
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

    /// Appends one incoming hit to the trace, trimming to the limit.
    func append(_ hit: CombatIncomingHit) {
        incomingHitCount += 1
        incomingTrace.append(hit)
        if incomingTrace.count > Self.traceLimit {
            incomingTrace.removeFirst(incomingTrace.count - Self.traceLimit)
        }
        playerDamageFlash = 1
    }

    /// Advances the opponent's clock by exactly one fixed step.
    ///
    /// Here rather than in the satellite because `driver` is `private(set)` and
    /// that is per file: the satellite drives the opponent but must not be able
    /// to rewrite its phase behind the runtime's back.
    func stepDevTargetDriver() -> DevTargetStep {
        driver.step(seconds: Self.fixedStepSeconds)
    }

    /// Parks the opponent's clock, for the same reason and with the same rule.
    func parkDevTargetDriver() {
        driver.park()
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

    /// One fixed step: the opponent acts, the state is re-derived, music
    /// follows the edge, the flash decays, and the caps are enforced.
    private func step() {
        guard let world else { return }
        driveDevTarget(world: world)
        state = CombatLoopState.derive(
            actors: world.combatActors(),
            hostility: { [weak world] key in world?.combatHostility(of: key) ?? .neutral },
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
