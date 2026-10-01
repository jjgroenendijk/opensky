// The combat shell over a fake world: what it reads, what it forwards, and the
// state it keeps. The rules are tested in `CombatCoreTests`.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct CombatCoordinatorTests {
    private static let guardKey = ReferenceKey.generated(1)

    private static func coordinator(_ world: FakeCoordinatorWorld) -> CombatCoordinator {
        let coordinator = CombatCoordinator()
        coordinator.attach(world: world)
        coordinator.wireMelee(settings: .synthetic, items: nil, impacts: nil)
        coordinator.wireArchery(settings: .synthetic, items: nil, impacts: nil)
        coordinator.wireLoop(settings: .synthetic)
        return coordinator
    }

    @Test func anUnwiredCoordinatorReportsItselfUnavailable() {
        let coordinator = CombatCoordinator()
        #expect(coordinator.meleeCombatSnapshot == .unavailable)
        #expect(coordinator.archerySnapshot == .unavailable)
        #expect(coordinator.combatLoopSnapshot == .unavailable)
        #expect(coordinator.requestMeleeAttack() == "Melee unavailable: no game data loaded.")
        #expect(coordinator.spawnDevProjectile() == "Archery unavailable: no game data loaded.")
    }

    @Test func meleeTargetsAreTheResidentActors() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.guardKey, feet: SIMD3(10, 0, 0))]
        let targets = Self.coordinator(world).meleeTargets()
        #expect(targets.map(\.key) == [Self.guardKey])
        #expect(targets.first?.feet == SIMD3(10, 0, 0))
    }

    @Test func theAttackMultiplierFoldsFortifyAndPerks() throws {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        #expect(coordinator.meleeAttackMultiplier(handType: .sword) == 1)
        let oneHanded = try #require(CombatFortifyBonus.oneHandedIndices.first)
        world.values[.player] = [oneHanded: 50]
        world.perkMultipliers[.player] = 2
        #expect(coordinator.meleeAttackMultiplier(handType: .sword) == 3)
    }

    @Test func zeroDamageNeverReachesTheWorld() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        #expect(!coordinator.applyMeleeDamage(0, to: Self.guardKey))
        #expect(coordinator.applyMeleeDamage(5, to: Self.guardKey))
        #expect(world.damage.map(\.amount) == [5])
    }

    @Test func onlyThePlayerGraphTakesAnEvent() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        #expect(!coordinator.raiseCombatEvent("staggerStart", on: Self.guardKey))
        #expect(coordinator.raiseCombatEvent("staggerStart", on: .player))
        #expect(coordinator.raiseArcheryEvent("bowDrawStart"))
        #expect(world.raisedEvents == ["staggerStart", "bowDrawStart"])
    }

    @Test func healthFractionReadsTheWorldAndIsFullWithoutValues() {
        let world = FakeCoordinatorWorld()
        world.healths[Self.guardKey] = (current: 30, maximum: 120)
        let coordinator = Self.coordinator(world)
        #expect(coordinator.combatHealthFraction(of: Self.guardKey) == 0.25)
        #expect(coordinator.combatHealthFraction(of: .generated(2)) == 1)
    }

    @Test func turningCastingOffAnswersNoSpellsWithoutAsking() {
        let world = FakeCoordinatorWorld()
        world.casting[Self.guardKey] = CombatCastingFacts(magicka: 50, spells: [])
        let coordinator = Self.coordinator(world)
        coordinator.isActorCastingEnabled = false
        #expect(coordinator.combatCasting(of: Self.guardKey) == .none)
        #expect(world.castingQueries.isEmpty)
        coordinator.isActorCastingEnabled = true
        #expect(coordinator.combatCasting(of: Self.guardKey).magicka == 50)
        #expect(world.castingQueries == [Self.guardKey])
    }

    @Test func onlyAFinishedReleaseCountsAsACast() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        let option = CombatSpellOption(spell: .generated(3), cost: 10, range: 1000)
        #expect(coordinator.releaseCombatCast(option, by: Self.guardKey))
        world.finishesCasts = false
        #expect(!coordinator.releaseCombatCast(option, by: Self.guardKey))
        #expect(coordinator.actorCastCount == 1)
        #expect(coordinator.combatLoopSnapshot.actorCastCount == 1)
    }

    @Test func aStuckArrowIsRemovedOnlyIfThisCoordinatorSpawnedIt() throws {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        let cell = CellSceneLocation.interior(FormID(0x500))
        let arrow = StuckProjectile(
            base: FormID(0x1397D), location: cell,
            position: SIMD3(1, 2, 3), rotation: SIMD3(), host: nil
        )
        let key = try #require(coordinator.spawnStuckProjectile(arrow))
        #expect(world.spawned.map(\.base) == [FormID(0x1397D)])
        coordinator.removeStuckProjectile(.generated(9999))
        coordinator.removeStuckProjectile(key)
        coordinator.removeStuckProjectile(key)
        #expect(world.resetKeys == [key])
    }

    @Test func transientsJoinTheProjectilesAndTheWorldsBodies() {
        let world = FakeCoordinatorWorld()
        world.bodyTransients = CombatTransientCounts(activeRagdolls: 2, awakeBodies: 5)
        world.trimmedBodies = CombatTransientCounts(activeRagdolls: 1, awakeBodies: 3)
        let coordinator = Self.coordinator(world)
        #expect(coordinator.combatTransients == CombatTransientCounts(
            activeRagdolls: 2, awakeBodies: 5
        ))
        let removed = coordinator.trimCombatTransients(to: .standard)
        #expect(removed == CombatTransientCounts(activeRagdolls: 1, awakeBodies: 3))
    }

    @Test func theHostilityControlActsOnTheSelectedActor() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.guardKey, feet: SIMD3(), name: "Guard")]
        let coordinator = Self.coordinator(world)
        coordinator.selectedActorIsHostile = true
        #expect(coordinator.combatLoopSnapshot.lastActionText
            == "Hostility: no resident actor to act on.")
        world.selected = Self.guardKey
        coordinator.selectedActorIsHostile = true
        #expect(world.hostilities[Self.guardKey] == .hostile)
        #expect(coordinator.selectedActorIsHostile)
        #expect(coordinator.combatLoopSnapshot.lastActionText == "Hostility: Guard is now hostile.")
    }
}
