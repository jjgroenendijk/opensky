// The combat shell over a fake world: what it reads, what it forwards, and the
// state it keeps. The rules are tested in `CombatCoreTests`.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct CombatCoordinatorTests {
    private static let guardKey = ReferenceKey.generated(1)

    private static func coordinator(_ world: FakeCoordinatorWorld) -> CombatCoordinator {
        CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    @Test func theConfidenceAndAssistanceSwitchFollowsTheSavedSetting() {
        let coordinator = CombatCoordinator(world: FakeCoordinatorWorld(), data: nil)
        let store = PlayerSettingsStore(persistence: nil)
        coordinator.load(settings: store)
        #expect(coordinator.usesCombatTemperament)
        store.set(.combatTemperament, to: 0)
        coordinator.load(settings: store)
        #expect(!coordinator.usesCombatTemperament)
    }

    @Test func aCoordinatorWithoutGameDataReportsItselfUnavailable() {
        let coordinator = CombatCoordinator(world: FakeCoordinatorWorld(), data: nil)
        #expect(coordinator.meleeCombatSnapshot == .unavailable)
        #expect(coordinator.archerySnapshot == .unavailable)
        #expect(coordinator.combatLoopSnapshot == .unavailable)
        #expect(coordinator.requestMeleeAttack().text == "Melee unavailable: no game data loaded.")
        #expect(coordinator.spawnDevProjectile()
            .text == "Archery unavailable: no game data loaded.")
    }

    @Test func theLoopReadsTheStyleTheWorldResolves() {
        let world = FakeCoordinatorWorld()
        let style = CombatStyleTuning(
            offensiveMultiplier: 1, defensiveMultiplier: 0.5, meleeScoreMultiplier: 1,
            magicScoreMultiplier: 1, name: "csTestBrute"
        )
        world.styles[Self.guardKey] = style
        let coordinator = Self.coordinator(world)
        #expect(coordinator.combatStyle(of: Self.guardKey) == style)
        #expect(coordinator.combatStyle(of: .player) == nil)
    }

    /// The HUD names the actor the player last hurt while it lives and stays
    /// near. A blow from anyone else does not change it.
    @Test func theEngagedEnemyIsTheLivingActorThePlayerHurt() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.guardKey, feet: SIMD3(10, 0, 0))]
        let coordinator = Self.coordinator(world)
        #expect(coordinator.engagedEnemy(playerFeet: .zero) == nil)
        coordinator.applyHealthDamage(5, to: Self.guardKey, attacker: nil)
        #expect(coordinator.engagedEnemy(playerFeet: .zero) == nil)
        coordinator.applyHealthDamage(5, to: Self.guardKey, attacker: .player)
        #expect(coordinator.engagedEnemy(playerFeet: .zero)?.key == Self.guardKey)
        let far = SIMD3<Float>(CombatCoordinator.enemyBarRange + 100, 0, 0)
        #expect(coordinator.engagedEnemy(playerFeet: far) == nil)
        world.actors = [
            CombatActorObservation(key: Self.guardKey, feet: SIMD3(10, 0, 0), isDead: true)
        ]
        #expect(coordinator.engagedEnemy(playerFeet: .zero) == nil)
    }

    @Test func meleeTargetsAreTheResidentActors() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.guardKey, feet: SIMD3(10, 0, 0))]
        let targets = Self.coordinator(world).meleeTargets()
        #expect(targets.map(\.key) == [Self.guardKey])
        #expect(targets.first?.feet == SIMD3(10, 0, 0))
    }

    /// The perks are in the strike, so a fortify effect alone moves this term.
    @Test func theAttackMultiplierFoldsFortify() throws {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        #expect(coordinator.meleeAttackMultiplier(handType: .sword) == 1)
        let oneHanded = try #require(CombatFortifyBonus.oneHandedIndices.first)
        world.values[.player] = [oneHanded: 50]
        world.perkFactors[.modAttackDamage] = 2
        #expect(coordinator.meleeAttackMultiplier(handType: .sword) == 1.5)
    }

    @Test func anUnawareTargetTakesASneakAttack() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        #expect(coordinator.strike(
            CombatBlow(attacker: .player, handType: .dagger),
            on: Self.guardKey
        )
        .sneakMultiplier == 3)
        world.detects[Self.guardKey] = [.player]
        #expect(!coordinator.strike(
            CombatBlow(attacker: .player, handType: .dagger),
            on: Self.guardKey
        )
        .isSneakAttack)
        #expect(!coordinator.strike(
            CombatBlow(attacker: Self.guardKey, handType: .dagger),
            on: .player
        )
        .isSneakAttack)
    }

    /// UESP "Skyrim:Sneak": a melee sneak attack gives 12 times the ranged experience.
    @Test func aSneakAttackGivesSneakExperienceAndANotice() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        _ = coordinator.meleeStrike(
            CombatBlow(attacker: .player, handType: .dagger),
            on: Self.guardKey
        )
        coordinator.applyProjectileDamage(5, to: Self.guardKey, from: .player)

        #expect(world.skillUses.map(\.action) == [.sneakAttack, .sneakAttack])
        #expect(world.skillUses.map(\.amount) == [30, 2.5])
        #expect(coordinator.takeCommands().first
            == .showNotification("sSuccessfulSneakAttackMain3.0sSuccessfulSneakAttackEnd"))
        world.detects[Self.guardKey] = [.player]
        _ = coordinator.meleeStrike(
            CombatBlow(attacker: .player, handType: .dagger),
            on: Self.guardKey
        )
        #expect(world.skillUses.count == 2)
    }

    @Test func thePlayersWeaponSkillScalesTheStrike() throws {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        world.detects[Self.guardKey] = [.player]
        let twoHanded = try #require(ActorValueIdentity.index(named: "Two-Handed"))
        world.values[.player] = [twoHanded: 100]
        world.values[Self.guardKey] = [twoHanded: 100]
        #expect(coordinator.strike(
            CombatBlow(attacker: .player, handType: .battleaxe),
            on: Self.guardKey
        )
        .skillMultiplier == 1.5)
        #expect(coordinator.strike(
            CombatBlow(attacker: Self.guardKey, handType: .battleaxe),
            on: .player
        )
        .skillMultiplier == 1)
    }

    @Test func aBlockCostsAQuarterOfTheIncomingBlow() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        let blocked = MeleeDamageResult(
            base: 20, blockedFraction: 0.5, applied: 10, attackMultiplier: 2
        )
        coordinator.applyBlockStamina(blocked, to: .player)
        #expect(world.staminaDamage.map(\.amount) == [10])
        #expect(world.staminaDamage.map(\.key) == [.player])
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
        #expect(coordinator.takeCommands() == [.removeReference(key)])
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
