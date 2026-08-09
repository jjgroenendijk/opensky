// The combat loop from breaking off to going back to work (issue #424, roadmap
// item 16.7): fleeing, losing the player, searching, giving up, dying, being
// calmed, script control, crowds, music, caps, persistence and determinism.
//
// The second half of the acceptance sentence `CombatLoopRuntimeTests` opens.
// Split for the strict lint type cap; the session both halves build lives in
// `CombatLoopFixture`.

@testable import opensky
import simd
import Testing

@MainActor
struct CombatLoopDisengageTests {
    private typealias Fixture = CombatLoopFixture

    // MARK: - Fleeing

    @Test func anActorAtTheFleeThresholdRunsAndStaysInTheFightWhileItDoes() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)

        world.healthFractions[Fixture.opponent] =
            CombatBehaviorSettings.standard.fleeHealthFraction
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.phase(of: Fixture.opponent) == .fleeing)
        #expect(runtime.state.isPlayerInCombat)
        // Away from the player, which stands at the origin.
        let destination = world.moveRequests.last?.point ?? .zero
        #expect(simd_length(destination) > simd_length(Fixture.closeFeet))
        #expect(world.musicChanges == [true])
    }

    @Test func aFleeingActorThatGotAwayLeavesCombatAndTheMusicStops() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        // Healthy long enough to be in the fight: an actor already under the
        // threshold never starts one.
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)
        world.healthFractions[Fixture.opponent] = 0.1
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.phase(of: Fixture.opponent) == .fleeing)

        world.place(
            Fixture.opponent,
            at: SIMD3(CombatBehaviorSettings.standard.fleeBreakDistance + 100, 0, 0)
        )
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.phase(of: Fixture.opponent) == .disengaged)
        #expect(!runtime.state.isPlayerInCombat)
        #expect(world.musicChanges == [true, false])
        #expect(world.packageResumes.contains(Fixture.opponent))
    }

    // MARK: - Losing the player, searching, giving up

    @Test func losingThePlayerSearchesTheLastKnownPositionAndReadsAsSearching() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)

        let remembered = SIMD3<Float>(120, 40, 0)
        world.awareness[Fixture.opponent] = CombatAwareness(
            state: .suspicious, lastKnownPosition: remembered
        )
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.phase(of: Fixture.opponent) == .searching)
        #expect(runtime.activity(of: Fixture.opponent) == .searching)
        #expect(runtime.state.searchingCount == 1)
        #expect(runtime.state.isPlayerInCombat)
        #expect(world.moveRequests.last?.point == remembered)
    }

    @Test func theSearchGivesUpAndHandsTheActorBackToItsPackage() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)

        world.awareness[Fixture.opponent] = CombatAwareness(
            state: .unaware, lastKnownPosition: SIMD3(120, 40, 0)
        )
        Fixture.run(runtime, seconds: CombatBehaviorSettings.standard.searchSeconds + 1)

        #expect(runtime.phase(of: Fixture.opponent) == .disengaged)
        #expect(runtime.activity(of: Fixture.opponent) == .notFighting)
        #expect(!runtime.state.isPlayerInCombat)
        #expect(world.packageResumes.contains(Fixture.opponent))
        // Still angry, which is why walking back into view starts it again.
        #expect(world.hostility[Fixture.opponent] == .hostile)
    }

    @Test func aGivenUpActorFightsAgainWhenItPerceivesThePlayerOnceMore() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)
        world.awareness[Fixture.opponent] = CombatAwareness(
            state: .unaware, lastKnownPosition: SIMD3(120, 40, 0)
        )
        Fixture.run(runtime, seconds: CombatBehaviorSettings.standard.searchSeconds + 1)
        #expect(!runtime.state.isPlayerInCombat)

        world.awareness[Fixture.opponent] = .detected(at: world.player.feet)
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.state.isPlayerInCombat)
        #expect(runtime.behaviors[Fixture.opponent]?.fightCount == 2)
    }

    // MARK: - Death and calming

    @Test func aDeadOpponentStopsAttackingAndEndsCombat() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)
        #expect(runtime.incomingHitCount == 1)

        world.kill(Fixture.opponent)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds * 2)

        #expect(runtime.incomingHitCount == 1)
        #expect(!runtime.state.isPlayerInCombat)
        #expect(runtime.state.deadCount == 1)
    }

    @Test func calmingAnActorEndsItsFightAndReturnsItToItsPackage() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.state.isPlayerInCombat)

        runtime.setHostility(.neutral, on: Fixture.opponent)
        Fixture.run(runtime, seconds: Fixture.cycleSeconds)

        #expect(!runtime.state.isPlayerInCombat)
        #expect(runtime.incomingHitCount == 0)
        #expect(world.packageResumes.contains(Fixture.opponent))
    }

    // MARK: - Script control

    @Test func startCombatFightsWithoutWaitingToPerceiveAnything() {
        let (runtime, world) = Fixture.session()
        #expect(runtime.startCombat(Fixture.opponent, with: .player))
        #expect(world.hostility[Fixture.opponent] == .hostile)

        Fixture.run(runtime, seconds: Fixture.cycleSeconds)

        #expect(runtime.state.isPlayerInCombat)
        #expect(runtime.incomingHitCount == 1)
    }

    @Test func startCombatRefusesATargetThisEngineDoesNotSimulate() {
        let (runtime, world) = Fixture.session()
        #expect(!runtime.startCombat(Fixture.opponent, with: Fixture.second))
        #expect(world.hostility.isEmpty)
    }

    @Test func startCombatRefusesAnActorThatIsNotResident() {
        let (runtime, _) = Fixture.session()
        #expect(!runtime.startCombat(Fixture.second, with: .player))
    }

    @Test func stopCombatEndsTheFightAndLeavesHostilityAlone() {
        let (runtime, world) = Fixture.session()
        runtime.startCombat(Fixture.opponent, with: .player)
        Fixture.run(runtime, seconds: 1)
        #expect(runtime.state.isPlayerInCombat)

        #expect(runtime.stopCombat(Fixture.opponent))
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)

        #expect(!runtime.state.isPlayerInCombat)
        #expect(world.hostility[Fixture.opponent] == .hostile)
        #expect(world.packageResumes.contains(Fixture.opponent))
    }

    @Test func stoppingAFightThatIsNotHappeningSaysSoRatherThanPretending() {
        let (runtime, _) = Fixture.session()
        #expect(!runtime.stopCombat(Fixture.opponent))
    }

    // MARK: - Crowds

    @Test func severalOpponentsFightAtOnceWithinTheEngagementCap() {
        let world = FakeCombatWorld()
        let keys = (1 ... CombatLoopRuntime.maximumEngagedActors + 2)
            .map { ReferenceKey.generated(UInt64($0)) }
        world.actors = keys.enumerated().map { index, key in
            CombatActorObservation(
                key: key, feet: SIMD3(Float(index) * 10 + 30, 0, 0), name: "Opponent \(index)"
            )
        }
        let runtime = CombatLoopRuntime(settings: .synthetic, world: world)
        runtime.behaviorSettings = CombatBehaviorSettings(blockChance: 0)
        for key in keys {
            Fixture.engage(runtime, world, key)
        }

        Fixture.run(runtime, seconds: 1)

        #expect(runtime.state.engagedCount == CombatLoopRuntime.maximumEngagedActors)
        #expect(runtime.crowdedOutCount == 2)
        // The nearest win, which is the stated rule.
        #expect(runtime.phase(of: keys[0])?.isEngaged == true)
        #expect(runtime.phase(of: keys[keys.count - 1]) == nil)
    }

    // MARK: - Music

    @Test func combatMusicFollowsTheEdgeRatherThanEveryStep() {
        let (runtime, world) = Fixture.session()
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 4)
        #expect(world.musicChanges.isEmpty)

        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 4)
        #expect(world.musicChanges == [true])

        runtime.setHostility(.neutral, on: Fixture.opponent)
        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 4)
        #expect(world.musicChanges == [true, false])
    }

    // MARK: - Bounds

    @Test func everyPopulationIsBroughtBackInsideItsCeiling() {
        let (runtime, world) = Fixture.session()
        runtime.limits = CombatTransientLimits(
            liveProjectiles: 1, stuckProjectiles: 1, activeRagdolls: 1, awakeBodies: 1
        )
        world.transients = CombatTransientCounts(
            liveProjectiles: 4, stuckProjectiles: 3, activeRagdolls: 2, awakeBodies: 9
        )

        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds)

        #expect(world.trimRequests == 1)
        #expect(runtime.trimmedTransients == CombatTransientCounts(
            liveProjectiles: 3, stuckProjectiles: 2, activeRagdolls: 1, awakeBodies: 8
        ))
    }

    @Test func nothingOverTheCeilingCostsNoTrim() {
        let (runtime, world) = Fixture.session()
        world.transients = CombatTransientCounts(liveProjectiles: 1)
        Fixture.run(runtime, seconds: 1)
        #expect(world.trimRequests == 0)
    }

    // MARK: - Persistence

    @Test func savingDropsWhatAReloadCannotReproduceAndKeepsWhatItCan() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        // Until the swing starts rather than for a counted duration: the exact
        // step depends on how many the actor spent closing first.
        var steps = 0
        while runtime.phase(of: Fixture.opponent) != .windup, steps < 600 {
            runtime.advance(by: CombatLoopRuntime.fixedStepSeconds)
            steps += 1
        }
        #expect(runtime.phase(of: Fixture.opponent) == .windup)

        runtime.prepareForPersistence()

        #expect(world.despawnRequests == 1)
        #expect(runtime.phase(of: Fixture.opponent) == .idle)
        #expect(runtime.playerDamageFlash == 0)
        // Hostility is a component and survives, which is what makes a reloaded
        // fight still a fight.
        #expect(world.hostility[Fixture.opponent] == .hostile)
    }

    @Test func aReloadedFightResumesFromPerceptionRatherThanMidSwing() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        Fixture.run(runtime, seconds: 1)
        runtime.prepareForPersistence()

        Fixture.run(runtime, seconds: CombatLoopRuntime.fixedStepSeconds * 2)

        #expect(runtime.phase(of: Fixture.opponent)?.isEngaged == true)
        #expect(runtime.behaviors[Fixture.opponent]?.attackCount == 0)
        #expect(runtime.state.isPlayerInCombat)
    }

    // MARK: - Determinism

    @Test func twoRunsOfTheSameLengthProduceTheSameFight() {
        let first = Fixture.session(blockChance: 0.35)
        let second = Fixture.session(blockChance: 0.35)
        Fixture.engage(first.runtime, first.world)
        Fixture.engage(second.runtime, second.world)

        Fixture.run(first.runtime, seconds: Fixture.cycleSeconds * 3)
        Fixture.run(second.runtime, seconds: Fixture.cycleSeconds * 3)

        #expect(first.runtime.state == second.runtime.state)
        #expect(first.runtime.behaviors == second.runtime.behaviors)
        #expect(first.runtime.incomingTrace == second.runtime.incomingTrace)
        #expect(first.world.damage == second.world.damage)
    }

    @Test func aZeroDeltaAdvancesNothing() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        #expect(runtime.advance(by: 0) == 0)
        #expect(runtime.advance(by: -1) == 0)
        #expect(runtime.advance(by: .nan) == 0)
        #expect(world.damage.isEmpty)
    }

    @Test func aLongStallRunsAtMostTheCappedNumberOfSteps() {
        let (runtime, world) = Fixture.session()
        Fixture.engage(runtime, world)
        #expect(runtime.advance(by: 30) == CombatLoopRuntime.maximumStepsPerAdvance)
    }
}
