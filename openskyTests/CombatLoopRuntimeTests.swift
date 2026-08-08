// The combat loop end to end (issue #374, roadmap item 15.7).
//
// This is the issue's headline acceptance: "a deterministic headless test runs
// the complete synthetic fight: hostility trigger, opponent attack damaging the
// player, a blocked attack reduced per formula, player melee and arrow hits,
// death at zero health, ragdoll hand-off, corpse loot transferring the
// inventory, and a save/load in the middle and at the end reproducing consistent
// state."
//
// The parts of that sentence this suite owns are the ones the loop itself
// decides: hostility, the opponent's blows, the block reduction on an incoming
// hit, the death that ends the fight, the music edge, the caps, and what a save
// drops. The rest already has a home and is not re-tested here —
// `MeleeCombatRuntimeTests` owns the player's swing, `ProjectileRuntimeTests`
// the arrow, `RagdollRuntimeTests` the hand-off and the corpse's inventory. The
// milestone gate (item 15.9) is what runs all of them as one route.
//
// Everything is driven by whole fixed steps against `FakeCombatWorld`, so the
// fight is a pure function of the step count and repeats exactly.

@testable import opensky
import simd
import Testing

@MainActor
struct CombatLoopRuntimeTests {
    private static let player = ReferenceKey.player
    private static let opponent = ReferenceKey.generated(1)

    /// A runtime over one opponent standing well inside unarmed reach.
    private static func session(
        weaponDamage: Float = 12
    ) -> (runtime: CombatLoopRuntime, world: FakeCombatWorld) {
        let world = FakeCombatWorld()
        world.actors = [CombatActorObservation(
            key: opponent, feet: SIMD3(60, 0, 0), name: "Opponent"
        )]
        let runtime = CombatLoopRuntime(settings: .synthetic, world: world)
        runtime.devTargetWeapon = MeleeWeaponProfile(damage: weaponDamage, reach: 1)
        return (runtime, world)
    }

    /// Advances `runtime` for `seconds`, one fixed step per call.
    ///
    /// One step per call rather than one long delta, because `advance(by:)`
    /// deliberately caps a single call at `maximumStepsPerAdvance` — that is the
    /// stall guard, and driving a two-second fight through it would silently
    /// simulate an eighth of a second.
    /// `aLongStallRunsAtMostTheCappedNumberOfSteps` is where the cap itself is
    /// pinned.
    private static func run(_ runtime: CombatLoopRuntime, seconds: Float) {
        var elapsed: Float = 0
        while elapsed < seconds {
            runtime.advance(by: CombatLoopRuntime.fixedStepSeconds)
            elapsed += CombatLoopRuntime.fixedStepSeconds
        }
    }

    /// One full attack cycle of the opponent, plus a step of slack.
    private static let cycleSeconds = DevTargetDriver.intervalSeconds
        + DevTargetDriver.windupSeconds
        + DevTargetDriver.recoverySeconds
        + CombatLoopRuntime.fixedStepSeconds

    // MARK: - Hostility

    @Test func anUntouchedActorIsNeutralAndTheWorldIsCalm() {
        let (runtime, world) = Self.session()
        #expect(world.actors.count == 1)
        Self.run(runtime, seconds: 1)
        #expect(runtime.hostility(of: Self.opponent) == .neutral)
        #expect(!runtime.state.isPlayerInCombat)
    }

    @Test func hittingAnActorMakesItHostile() {
        let (runtime, world) = Self.session()
        #expect(runtime.provoke(Self.opponent))
        #expect(world.hostility[Self.opponent] == .hostile)
        Self.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)
        #expect(runtime.state.isPlayerInCombat)
        #expect(runtime.state.target == Self.opponent)
    }

    @Test func provokingTwiceWritesOnce() {
        let (runtime, world) = Self.session()
        #expect(runtime.provoke(Self.opponent))
        #expect(!runtime.provoke(Self.opponent))
        #expect(world.hostilityWrites == 1)
    }

    @Test func thePlayerCannotBeProvoked() {
        let (runtime, world) = Self.session()
        #expect(!runtime.provoke(.player))
        #expect(world.hostility.isEmpty)
    }

    // MARK: - The opponent

    @Test func theDevTargetIsSpawnedHostileAndAttacksThePlayer() {
        let (runtime, world) = Self.session(weaponDamage: 12)
        _ = runtime.spawnDevTarget()
        #expect(runtime.devTarget == Self.opponent)
        #expect(world.hostility[Self.opponent] == .hostile)

        Self.run(runtime, seconds: Self.cycleSeconds)

        #expect(runtime.incomingHitCount == 1)
        #expect(world.damage[.player] == 12)
        #expect(runtime.driver.contactCount == 1)
    }

    @Test func aBlockedBlowIsReducedByThePinnedFormula() {
        let (runtime, world) = Self.session(weaponDamage: 12)
        world.blocks[.player] = .weapon
        _ = runtime.spawnDevTarget()

        Self.run(runtime, seconds: Self.cycleSeconds)

        let expected = MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 12, reach: 1),
            block: .weapon,
            settings: .synthetic
        )
        #expect(expected.wasBlocked)
        #expect(runtime.incomingTrace.last?.damage == expected)
        #expect(world.damage[.player] == expected.applied)
    }

    @Test func aBlowOutOfReachLandsNothing() {
        let (runtime, world) = Self.session()
        world.actors = [CombatActorObservation(
            key: Self.opponent, feet: SIMD3(4000, 0, 0), name: "Opponent"
        )]
        _ = runtime.spawnDevTarget()

        Self.run(runtime, seconds: Self.cycleSeconds)

        #expect(runtime.driver.contactCount == 1)
        #expect(runtime.incomingHitCount == 0)
        #expect(world.damage[.player] == nil)
    }

    @Test func aLandedBlowRaisesTheCensusNamedHitReactionMagnitudeFirst() {
        let (runtime, world) = Self.session(weaponDamage: 7)
        _ = runtime.spawnDevTarget()

        Self.run(runtime, seconds: Self.cycleSeconds)

        #expect(world.raised.contains(CombatGraphNames.recoilStart))
        #expect(world.variables[CombatGraphNames.recoilMagnitude] == .real(7))
        #expect(world.wroteMagnitudeBeforeRecoil)
        #expect(runtime.incomingTrace.last?.playedReaction == true)
    }

    @Test func theDamageFlashDecaysToZero() {
        // The world is bound rather than discarded: `CombatLoopRuntime` holds
        // it weakly, exactly as the other directors hold theirs, so a `_` here
        // would let ARC free it and the fight would silently not happen.
        let (runtime, world) = Self.session()
        #expect(world.actors.count == 1)
        _ = runtime.spawnDevTarget()
        // Sampled on the step the blow lands rather than at the end of the run:
        // the flash is raised inside that step and decays from the same step
        // onward, so by the end of the opponent's recovery — which is longer
        // than the decay — it is legitimately back at zero. Both halves matter,
        // so both are observed.
        var flashAtBlow: Float = 0
        var elapsed: Float = 0
        while elapsed < Self.cycleSeconds {
            runtime.advance(by: CombatLoopRuntime.fixedStepSeconds)
            elapsed += CombatLoopRuntime.fixedStepSeconds
            if runtime.incomingHitCount == 1, flashAtBlow == 0 {
                flashAtBlow = runtime.playerDamageFlash
            }
        }

        #expect(runtime.incomingHitCount == 1)
        #expect(flashAtBlow > 0.9)
        #expect(runtime.playerDamageFlash == 0)
    }

    @Test func theOpponentPlaysItsAttackClipWhenTheAttackStarts() {
        let (runtime, world) = Self.session()
        _ = runtime.spawnDevTarget()
        Self.run(runtime, seconds: Self.cycleSeconds)
        #expect(world.clips.contains { $0.clip == .attack && $0.key == Self.opponent })
    }

    @Test func hittingTheOpponentStaggersItAndPlaysTheStaggerClip() {
        let (runtime, world) = Self.session()
        _ = runtime.spawnDevTarget()
        Self.run(runtime, seconds: DevTargetDriver.intervalSeconds)

        runtime.notePlayerHits([Self.opponent])

        #expect(runtime.driver.phase == .staggered)
        #expect(world.clips.contains { $0.clip == .stagger && $0.key == Self.opponent })
    }

    @Test func aDeadOpponentStopsAttackingAndEndsCombat() {
        let (runtime, world) = Self.session()
        _ = runtime.spawnDevTarget()
        Self.run(runtime, seconds: Self.cycleSeconds)
        #expect(runtime.incomingHitCount == 1)

        world.actors = [CombatActorObservation(
            key: Self.opponent, feet: SIMD3(60, 0, 0), isDead: true, name: "Opponent"
        )]
        Self.run(runtime, seconds: Self.cycleSeconds * 2)

        #expect(runtime.incomingHitCount == 1)
        #expect(!runtime.state.isPlayerInCombat)
        #expect(runtime.state.deadCount == 1)
    }

    @Test func resettingTheDevTargetCalmsItAndStopsTheClock() {
        let (runtime, world) = Self.session()
        _ = runtime.spawnDevTarget()
        _ = runtime.resetDevTarget()

        Self.run(runtime, seconds: Self.cycleSeconds * 2)

        #expect(runtime.devTarget == nil)
        #expect(world.hostility[Self.opponent] == .neutral)
        #expect(runtime.incomingHitCount == 0)
        #expect(!runtime.state.isPlayerInCombat)
    }

    @Test func spawningWithNoLivingActorSaysSoRatherThanPretending() {
        let (runtime, world) = Self.session()
        world.actors = []
        let outcome = runtime.spawnDevTarget()
        #expect(outcome.contains("no living actor"))
        #expect(runtime.devTarget == nil)
    }

    // MARK: - Music

    @Test func combatMusicFollowsTheEdgeRatherThanEveryStep() {
        let (runtime, world) = Self.session()
        Self.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 4)
        #expect(world.musicChanges.isEmpty)

        _ = runtime.spawnDevTarget()
        Self.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 4)
        #expect(world.musicChanges == [true])

        _ = runtime.resetDevTarget()
        Self.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 4)
        #expect(world.musicChanges == [true, false])
    }

    // MARK: - Bounds

    @Test func everyPopulationIsBroughtBackInsideItsCeiling() {
        let (runtime, world) = Self.session()
        runtime.limits = CombatTransientLimits(
            liveProjectiles: 1, stuckProjectiles: 1, activeRagdolls: 1, awakeBodies: 1
        )
        world.transients = CombatTransientCounts(
            liveProjectiles: 4, stuckProjectiles: 3, activeRagdolls: 2, awakeBodies: 9
        )

        Self.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)

        #expect(world.trimRequests == 1)
        #expect(runtime.trimmedTransients == CombatTransientCounts(
            liveProjectiles: 3, stuckProjectiles: 2, activeRagdolls: 1, awakeBodies: 8
        ))
    }

    @Test func nothingOverTheCeilingCostsNoTrim() {
        let (runtime, world) = Self.session()
        world.transients = CombatTransientCounts(liveProjectiles: 1)
        Self.run(runtime, seconds: 1)
        #expect(world.trimRequests == 0)
    }

    // MARK: - Persistence

    @Test func savingDropsWhatAReloadCannotReproduceAndKeepsWhatItCan() {
        let (runtime, world) = Self.session()
        _ = runtime.spawnDevTarget()
        Self.run(runtime, seconds: DevTargetDriver.intervalSeconds)
        #expect(runtime.driver.phase == .windup)

        runtime.prepareForPersistence()

        #expect(world.despawnRequests == 1)
        #expect(runtime.driver.phase == .idle)
        #expect(runtime.playerDamageFlash == 0)
        // Hostility is a component and survives, which is what makes a reloaded
        // fight still a fight.
        #expect(world.hostility[Self.opponent] == .hostile)
    }

    // MARK: - Determinism

    @Test func twoRunsOfTheSameLengthProduceTheSameFight() {
        let first = Self.session()
        let second = Self.session()
        _ = first.runtime.spawnDevTarget()
        _ = second.runtime.spawnDevTarget()

        Self.run(first.runtime, seconds: Self.cycleSeconds * 3)
        Self.run(second.runtime, seconds: Self.cycleSeconds * 3)

        #expect(first.runtime.state == second.runtime.state)
        #expect(first.runtime.driver == second.runtime.driver)
        #expect(first.runtime.incomingTrace == second.runtime.incomingTrace)
        #expect(first.world.damage == second.world.damage)
    }

    @Test func aZeroDeltaAdvancesNothing() {
        let (runtime, world) = Self.session()
        _ = runtime.spawnDevTarget()
        #expect(runtime.advance(by: 0) == 0)
        #expect(runtime.advance(by: -1) == 0)
        #expect(runtime.advance(by: .nan) == 0)
        #expect(world.damage.isEmpty)
    }

    @Test func aLongStallRunsAtMostTheCappedNumberOfSteps() {
        let (runtime, world) = Self.session()
        #expect(world.actors.count == 1)
        _ = runtime.spawnDevTarget()
        #expect(runtime.advance(by: 30) == CombatLoopRuntime.maximumStepsPerAdvance)
    }
}

/// The session `CombatLoopRuntime` runs over, as a recording fake.
@MainActor
final class FakeCombatWorld: CombatLoopWorld {
    var player = MeleeAttacker(key: .player, feet: SIMD3<Float>(), facing: 0)
    var actors: [CombatActorObservation] = []
    var hostility: [ReferenceKey: ActorHostility] = [:]
    var blocks: [ReferenceKey: MeleeBlockKind] = [:]
    var transients = CombatTransientCounts.none

    private(set) var hostilityWrites = 0
    private(set) var damage: [ReferenceKey: Float] = [:]
    private(set) var raised: [String] = []
    private(set) var variables: [String: BehaviorVariableValue] = [:]
    private(set) var clips: [(clip: CombatActorClip, key: ReferenceKey)] = []
    private(set) var musicChanges: [Bool] = []
    private(set) var trimRequests = 0
    private(set) var despawnRequests = 0
    /// True when `recoilMagnitude` was written before `recoilStart` was raised,
    /// which is the write-then-raise order the graph depends on.
    private(set) var wroteMagnitudeBeforeRecoil = false

    var combatPlayer: MeleeAttacker {
        player
    }

    func combatActors() -> [CombatActorObservation] {
        actors
    }

    func combatHostility(of key: ReferenceKey) -> ActorHostility {
        hostility[key] ?? .neutral
    }

    @discardableResult
    func setCombatHostility(_ value: ActorHostility, on key: ReferenceKey) -> Bool {
        guard hostility[key] != value else { return false }
        hostility[key] = value
        hostilityWrites += 1
        return true
    }

    @discardableResult
    func applyCombatDamage(_ amount: Float, to key: ReferenceKey) -> Bool {
        guard amount > 0 else { return false }
        damage[key, default: 0] += amount
        return true
    }

    func combatBlock(of key: ReferenceKey) -> MeleeBlockKind? {
        blocks[key]
    }

    @discardableResult
    func raiseCombatEvent(_ name: String, on target: ReferenceKey?) -> Bool {
        if
            name == CombatGraphNames.recoilStart,
            variables[CombatGraphNames.recoilMagnitude] != nil
        {
            wroteMagnitudeBeforeRecoil = true
        }
        raised.append(name)
        return target == nil
    }

    func writeCombatVariable(_ value: BehaviorVariableValue, named name: String) {
        variables[name] = value
    }

    @discardableResult
    func playCombatClip(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        clips.append((clip: clip, key: key))
        return true
    }

    var combatTransients: CombatTransientCounts {
        transients
    }

    @discardableResult
    func trimCombatTransients(to limits: CombatTransientLimits) -> CombatTransientCounts {
        trimRequests += 1
        let removed = limits.excess(over: transients)
        transients = CombatTransientCounts(
            liveProjectiles: transients.liveProjectiles - removed.liveProjectiles,
            stuckProjectiles: transients.stuckProjectiles - removed.stuckProjectiles,
            activeRagdolls: transients.activeRagdolls - removed.activeRagdolls,
            awakeBodies: transients.awakeBodies - removed.awakeBodies
        )
        return removed
    }

    func despawnCombatTransients() {
        despawnRequests += 1
        transients = .none
    }

    func setCombatMusicActive(_ active: Bool) {
        musicChanges.append(active)
    }
}
