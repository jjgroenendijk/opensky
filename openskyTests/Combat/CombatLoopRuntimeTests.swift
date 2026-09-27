// The combat loop from hostility to a landed blow (issues #374 and #424,
// roadmap items 15.7 and 16.7).
//
// 16.7's headline acceptance is "deterministic tests run the full synthetic
// loop: detect, approach along a navmesh, attack with real damage, a player
// block reducing it, an NPC block reducing the player's hit, stagger
// interrupting the attack, flee at the threshold, loss of the hidden player,
// search, give-up, and package resumption". This file owns that sentence up to
// the stagger; `CombatLoopDisengageTests` owns the rest. Both drive whole fixed
// steps against `FakeCombatWorld`, so a fight is a pure function of the step
// count and repeats exactly.
//
// What these suites do not re-test has a home: `CombatBehaviorMachineTests`
// owns the decisions on their own, `MeleeCombatRuntimeTests` the player's
// swing, `ProjectileRuntimeTests` the arrow, `RagdollRuntimeTests` the hand-off
// and the corpse's inventory. The milestone gates run all of them as one route.

@testable import opensky
import simd
import Testing

@MainActor
struct CombatLoopRuntimeTests {
    private typealias Fixture = CombatLoopFixture

    // MARK: - Hostility and entry

    @Test func anUntouchedActorIsNeutralAndTheWorldIsCalm() {
        let (runtime, world) = Fixture.session()
        #expect(world.actors.count == 1)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.hostility(of: Fixture.opponent) == .neutral)
        #expect(!runtime.state.isPlayerInCombat)
    }

    @Test func hittingAnActorMakesItHostileAndPutsItInTheFight() {
        let (runtime, world) = Fixture.session()
        runtime.notePlayerHits([Fixture.opponent])
        #expect(world.hostility[Fixture.opponent] == .hostile)

        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.state.isPlayerInCombat)
        #expect(runtime.state.target == Fixture.opponent)
        #expect(runtime.activity(of: Fixture.opponent) != .notFighting)
    }

    @Test func provokingTwiceWritesOnce() {
        let (runtime, world) = Fixture.session()
        #expect(runtime.provoke(Fixture.opponent))
        #expect(!runtime.provoke(Fixture.opponent))
        #expect(world.hostilityWrites == 1)
    }

    @Test func thePlayerCannotBeProvoked() {
        let (runtime, world) = Fixture.session()
        #expect(!runtime.provoke(.player))
        #expect(world.hostility.isEmpty)
    }

    /// Scope point 5: detection of an actor the world already marks hostile
    /// starts the fight without waiting for damage.
    @Test func aHostileActorThatPerceivesThePlayerStartsFightingUnhit() {
        let (runtime, world) = Fixture.session()
        runtime.setHostility(.hostile, on: Fixture.opponent)
        Fixture.run(runtime, seconds: 1)
        #expect(!runtime.state.isPlayerInCombat)
        #expect(runtime.phase(of: Fixture.opponent) == .idle)

        world.awareness[Fixture.opponent] = .detected(at: world.player.feet)
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.state.isPlayerInCombat)
        #expect(runtime.state.engagedCount == 1)
        #expect(world.damage[.player] == nil)
    }

    @Test func hostilityWithoutPerceptionIsNotYetCombat() {
        let (runtime, world) = Fixture.session()
        runtime.setHostility(.hostile, on: Fixture.opponent)
        Fixture.run(runtime, seconds: 4)
        #expect(runtime.state.hostileCount == 1)
        #expect(runtime.state.engagedCount == 0)
        #expect(!runtime.state.isPlayerInCombat)
        #expect(world.musicChanges.isEmpty)
    }

    // MARK: - Approach

    @Test func anActorOutOfReachWalksTowardThePlayerThroughTheMover() {
        let (runtime, world) = Fixture.session(feet: Fixture.farFeet)
        Fixture.engage(runtime, world)

        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.phase(of: Fixture.opponent) == .approaching)
        #expect(world.moveRequests.first?.key == Fixture.opponent)
        #expect(world.moveRequests.first?.point == world.player.feet)
        #expect(world.damage[.player] == nil)
    }

    @Test func arrivingInsideReachStopsTheWalkAndStartsTheAttackCadence() {
        let (runtime, world) = Fixture.session(feet: Fixture.farFeet)
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)

        // What the mover would have done by now.
        world.place(Fixture.opponent, at: Fixture.closeFeet)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)

        #expect(world.stopRequests.contains(Fixture.opponent))
        #expect(runtime.incomingHitCount == 1)
        #expect(world.damage[.player] == 12)
    }

    // MARK: - Attacking

    @Test func anEngagedActorAttacksThePlayerThroughTheShippingDamagePath() {
        let (runtime, world) = Fixture.session(weaponDamage: 12)
        Fixture.engage(runtime, world)

        Fixture.run(runtime, seconds: Fixture.cycleSeconds)

        #expect(runtime.incomingHitCount == 1)
        #expect(world.damage[.player] == 12)
        #expect(runtime.behaviors[Fixture.opponent]?.contactCount == 1)
    }

    @Test func aBlockedBlowIsReducedByThePinnedFormula() {
        let (runtime, world) = Fixture.session(weaponDamage: 12)
        world.blocks[.player] = .weapon
        Fixture.engage(runtime, world)

        Fixture.run(runtime, seconds: Fixture.cycleSeconds)

        let expected = MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 12, reach: 1),
            block: .weapon,
            settings: .synthetic
        )
        #expect(expected.wasBlocked)
        #expect(runtime.incomingTrace.last?.damage == expected)
        #expect(world.damage[.player] == expected.applied)
    }

    /// Scope point 2, the other direction: an NPC's raised guard is what
    /// `combatBlock(of:)` answers for it, so the player's own hit resolves
    /// through the same formula.
    @Test func anNPCsRaisedGuardIsWhatTheBlockSeamAnswers() {
        let (runtime, world) = Fixture.session(blockChance: 1)
        Fixture.engage(runtime, world)

        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.phase(of: Fixture.opponent) == .blocking)
        #expect(runtime.blockKind(of: Fixture.opponent) == .weapon)

        let blocked = MeleeDamage.resolve(
            weapon: MeleeWeaponProfile(damage: 20, reach: 1),
            block: runtime.blockKind(of: Fixture.opponent),
            settings: .synthetic
        )
        #expect(blocked.wasBlocked)
        #expect(blocked.applied < 20)
    }

    @Test func anActorWithItsGuardDownBlocksNothing() {
        let (runtime, world) = Fixture.session(blockChance: 0)
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 4)
        #expect(runtime.blockKind(of: Fixture.opponent) == nil)
    }

    @Test func aBlowOutOfReachLandsNothing() {
        let (runtime, world) = Fixture.session(feet: Fixture.farFeet)
        // Forced, so the actor keeps swinging where it stands rather than
        // needing a mover this fake does not run.
        runtime.startCombat(Fixture.opponent, with: .player)
        world.movementSucceeds = false

        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 2)

        #expect(runtime.incomingHitCount == 0)
        #expect(world.damage[.player] == nil)
    }

    @Test func aLandedBlowRaisesTheCensusNamedHitReactionMagnitudeFirst() {
        let (runtime, world) = Fixture.session(weaponDamage: 7)
        Fixture.engage(runtime, world)

        Fixture.run(runtime, seconds: Fixture.cycleSeconds)

        #expect(world.raised.contains(CombatGraphNames.recoilStart))
        #expect(world.variables[CombatGraphNames.recoilMagnitude] == .real(7))
        #expect(world.wroteMagnitudeBeforeRecoil)
        #expect(runtime.incomingTrace.last?.playedReaction == true)
    }

    @Test func theDamageFlashDecaysToZero() {
        // The world is bound rather than discarded: `CombatLoopRuntime` holds
        // it weakly, exactly as the other directors hold theirs, so a `_` here
        // would let ARC free it and the fight would silently not happen.
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        // Sampled on the step the blow lands rather than at the end of the run:
        // the flash is raised inside that step and decays from the same step
        // onward, so by the end of the recovery — which is longer than the
        // decay — it is legitimately back at zero.
        var flashAtBlow: Float = 0
        var elapsed: Float = 0
        while elapsed < Fixture.cycleSeconds {
            runtime.advance(by: CombatLoopRuntime.fixedStepSeconds)
            elapsed += CombatLoopRuntime.fixedStepSeconds
            if runtime.incomingHitCount == 1, flashAtBlow == 0 {
                flashAtBlow = runtime.playerDamageFlash
            }
        }

        #expect(runtime.incomingHitCount == 1)
        #expect(flashAtBlow > 0.9)
        // Not `== 0`: the decay is a float subtraction per step and lands a
        // rounding error short of zero on some step counts.
        #expect(runtime.playerDamageFlash < 0.001)
    }

    @Test func theOpponentPlaysItsAttackClipWhenTheAttackStarts() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)
        #expect(world.clips.contains { $0.clip == .attack && $0.key == Fixture.opponent })
    }

    @Test func hittingTheOpponentStaggersItAndPlaysTheStaggerClip() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: CombatBehaviorSettings.standard.attackIntervalSeconds)

        runtime.notePlayerHits([Fixture.opponent])

        #expect(runtime.phase(of: Fixture.opponent) == .staggered)
        #expect(world.clips.contains { $0.clip == .stagger && $0.key == Fixture.opponent })
    }
}
