// The melee and projectile worlds over a fake `CombatWorld`: the reads of the
// shared strike, block, and perk parts, and the commands each request queues.

@testable import OpenSkyActorsInterface
import OpenSkyBehavior
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct CombatHitPartsTests {
    private static let foe = ReferenceKey.generated(7)
    private static let staminaIndex = ActorValueIdentity.index(named: "Stamina") ?? 0

    private static func coordinator(_ world: FakeCoordinatorWorld) -> CombatCoordinator {
        CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    @Test func theMeleeWorldReadsTheBlockAndPerkParts() {
        let world = FakeCoordinatorWorld()
        world.perkFactors[.modPowerAttackStamina] = 2
        let part = Self.coordinator(world).meleeWorld
        let blow = CombatBlow(attacker: .player, handType: .sword, baseDamage: 8)
        #expect(part.meleeBlock(of: Self.foe) == nil)
        #expect(part.meleeBlockSkill(of: Self.foe) == MeleeDamage.defaultBlockSkill)
        #expect(part.meleeBlockMultiplier(of: Self.foe) == 1)
        #expect(part.meleeResolvedWeapon(nil) == nil)
        #expect(!part.meleeSweeps(blow))
        #expect(part.meleePowerAttackStamina(5, weapon: nil) == 10)
        part.applyMeleeHitSpell(blow, on: Self.foe)
        #expect(world.spellHits.isEmpty)
        #expect(!part.canPowerBash())
        #expect(part.meleeBashSource().shieldRating == nil)
    }

    @Test func meleeStaminaIsPaidOnlyWithStaminaLeft() {
        let world = FakeCoordinatorWorld()
        let part = Self.coordinator(world).meleeWorld
        #expect(part.payMeleeStamina(10))
        #expect(world.staminaDamage.isEmpty)
        world.values[.player] = [Self.staminaIndex: 50]
        #expect(part.payMeleeStamina(10))
        #expect(world.staminaDamage.map(\.amount) == [10])
        world.values[.player] = [Self.staminaIndex: 0]
        #expect(!part.payMeleeStamina(10))
    }

    @Test func impactsAreQueuedAsCommands() {
        let coordinator = Self.coordinator(FakeCoordinatorWorld())
        let impact = ResolvedMeleeImpact(sound: FormID(0x51))
        let at = SIMD3<Float>(1, 2, 3)
        coordinator.meleeWorld.playMeleeImpact(impact, at: at)
        #expect(coordinator.takeCommands() == [.playImpact(impact, at: at)])
        coordinator.projectileWorld.playProjectileImpact(impact, at: at)
        coordinator.projectileWorld.showArcheryNotice("No arrows")
        #expect(coordinator.takeCommands() == [
            .playImpact(impact, at: at), .detectionEvent(owner: .player, at: at),
            .showNotification("No arrows")
        ])
    }

    @Test func theProjectileWorldReadsTheResidentWorld() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.foe, feet: SIMD3(5, 0, 0))]
        world.perkMultipliers[.player] = 1.5
        let coordinator = Self.coordinator(world)
        let part = coordinator.projectileWorld
        #expect(coordinator.projectileTargets().map(\.key) == [Self.foe])
        let query = ShapeSweepQuery.sphere(
            center: .zero, radius: 1, direction: SIMD3(1, 0, 0), maximumDistance: 10
        )
        #expect(coordinator.sweepProjectile(query) == nil)
        #expect(part.residentProjectileCells().isEmpty)
        #expect(part.projectileIsSneakAttack(by: .player, on: Self.foe))
        #expect(!part.projectileIsSneakAttack(by: Self.foe, on: .player))
        #expect(!part.consumeArrow(FormID(0x1)))
        #expect(!part.giveRecoveredArrow(FormID(0x1), to: Self.foe))
        #expect(part.arrowRecoveryMultiplier(of: .player) == 1.5)
        part.writeArcheryVariable(.real(0.5), named: "fBowDrawn")
    }

    @Test func aLaunchWithAMuzzleFlashQueuesIt() {
        let coordinator = Self.coordinator(FakeCoordinatorWorld())
        let runtime = ProjectileRuntime(settings: .synthetic, world: coordinator.projectileWorld)
        var profile = ProjectileProfile(
            speed: 1000,
            gravityFactor: 0,
            range: 4000,
            collisionRadius: 2
        )
        profile.visuals.muzzleFlashModel = "effects\\flash.nif"
        profile.visuals.muzzleFlashDuration = 0.1
        _ = runtime.fire(ProjectileShot.arrow(
            profile: profile,
            damage: ArcheryDamage.resolve(bowDamage: 10, arrowDamage: 0, skill: 0),
            weapon: FormID(0x0001_397E)
        ))
        let flashes = coordinator.takeCommands().filter {
            if case .muzzleFlash = $0 {
                return true
            }
            return false
        }
        #expect(flashes.count == 1)
    }
}

/// The rule parts over the shared state: damage, falls, difficulty, gear, and perks.
@MainActor
struct CombatRulePartsTests {
    private static let foe = ReferenceKey.generated(7)

    private static func coordinator(_ world: FakeCoordinatorWorld) -> CombatCoordinator {
        CombatCoordinator(
            world: world, data: CombatSessionData(combat: .synthetic, archery: .synthetic)
        )
    }

    @Test func aHardFallHurtsAndIsRemembered() {
        let world = FakeCoordinatorWorld()
        let coordinator = Self.coordinator(world)
        #expect(coordinator.applyFall(height: 2000, speed: 3000, to: Self.foe) > 0)
        #expect(coordinator.lastFall?.actor == Self.foe)
        #expect(world.damage.map(\.key) == [Self.foe])
        #expect(coordinator.applyFall(height: 1, speed: 1, to: Self.foe) == 0)
    }

    @Test func aKnockBackNeedsHealthAndAnImpulseWorld() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.foe, feet: SIMD3(50, 0, 0))]
        let coordinator = Self.coordinator(world)
        #expect(coordinator.forceKnockBack(Self.foe, damage: 90) == nil)
        world.healths[Self.foe] = (current: 10, maximum: 100)
        #expect(coordinator.impulses == nil)
        #expect(coordinator.forceKnockBack(Self.foe, damage: 90) == nil)
        let impulseWorld = FakeImpulseWorld()
        coordinator.explosions.impulses = ImpulseRuntime(world: impulseWorld)
        let knock = coordinator.forceKnockBack(Self.foe, damage: 90)
        #expect((knock != nil) == !(impulseWorld.knocks.isEmpty && impulseWorld.downs.isEmpty))
    }

    @Test func onlyThePlayersDestructionUseFollowsTheDifficulty() {
        let coordinator = Self.coordinator(FakeCoordinatorWorld())
        coordinator.difficulty = .legendary
        #expect(coordinator.difficulty == .legendary)
        let use = SkillUseEvent(
            actor: .player, action: .spellEffect(skill: CombatShared.CombatDamage.destructionIndex),
            amount: 10
        )
        #expect(coordinator.adjustingForDifficulty(use).actor == .player)
        let other = SkillUseEvent(actor: Self.foe, action: .sneakAttack, amount: 10)
        #expect(coordinator.adjustingForDifficulty(other) == other)
    }

    @Test func theBowZoomRunsAtFullSpeedWhenNotZoomed() {
        let coordinator = Self.coordinator(FakeCoordinatorWorld())
        coordinator.isTimeSlowed = true
        #expect(coordinator.isTimeSlowed)
        #expect(coordinator.bowZoomTimeScale == 1)
        #expect(coordinator.shared.gear.bowZoomConditions(bow: nil).timeIsSlowed)
    }

    @Test func thePerkTermsReadTheirEntryPoints() {
        let world = FakeCoordinatorWorld()
        world.perkFactors[.modBowZoom] = 0.5
        world.perkFactors[.modFallingDamage] = 0.25
        world.perkMultipliers[.player] = 2
        let perks = Self.coordinator(world).shared.perks
        #expect(perks.bowZoomViewShare(bow: nil) == 0.5)
        #expect(perks.fallingDamage(40, on: .player) == 10)
        #expect(perks.arrowRecoveryMultiplier(of: .player) == 2)
    }

    @Test func aFrameOfMeleeAndArcheryRunsWithoutGear() {
        let coordinator = Self.coordinator(FakeCoordinatorWorld())
        #expect(coordinator.melee != nil && coordinator.loop != nil)
        #expect(coordinator.items == nil)
        coordinator.isWeaponDrawn = true
        _ = coordinator.isWeaponDrawn
        _ = coordinator.advanceMelee(events: [], intent: .still, isPlayerControlled: true)
        let commands = coordinator.advanceArchery(
            events: [], intent: .still, isPlayerControlled: true, delta: 1.0 / 60
        )
        #expect(commands.isEmpty)
    }

    @Test func thePanelSwitchesWriteTheSharedState() {
        let coordinator = Self.coordinator(FakeCoordinatorWorld())
        coordinator.usesCombatTemperament = false
        #expect(!coordinator.shared.usesTemperament)
        coordinator.isActorCastingEnabled = false
        #expect(!coordinator.isActorCastingEnabled)
    }

    @Test func theCoordinatorAnswersForTheWorldsActors() {
        let world = FakeCoordinatorWorld()
        world.actors = [CombatActorObservation(key: Self.foe, feet: .zero)]
        world.hostilities[Self.foe] = .hostile
        let coordinator = Self.coordinator(world)
        #expect(coordinator.combatActor(key: Self.foe)?.key == Self.foe)
        #expect(coordinator.combatHostility(of: Self.foe) == .hostile)
    }
}

/// The ragdoll loader built over a collision library finds nothing for a missing model.
@MainActor
struct RagdollDefinitionLoadingTests {
    @Test func aMissingSkeletonModelLoadsNoRagdoll() {
        let library = NIFCollisionLibrary(fileSystem: InMemoryFileSource())
        let load = RagdollDefinitionLoading.definitionLoader(library)
        #expect(load("actors\\missing.nif", FakeRagdollSessionWorld.skeleton, 1) == nil)
    }
}
