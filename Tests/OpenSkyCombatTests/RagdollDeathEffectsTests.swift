// The death effects against a fake world: the push of the killing hit, the weapon
// drop, the head cut and its fall, and the excess-dead rule.

@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyEngineTesting
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct RagdollDeathEffectsTests {
    private static let victim = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x201)

    private static func session(
        settings: DeathSettings = .vanilla
    ) -> (RagdollCoordinator, FakeRagdollSessionWorld) {
        let world = FakeRagdollSessionWorld()
        world.ragdollResidents = [RagdollResident(key: victim, position: SIMD3(100, 0, 0))]
        let coordinator = RagdollCoordinator(
            store: WorldStateStore(),
            world: world,
            data: RagdollSessionData(
                loadDefinition: { _, _, _ in RagdollFixture.limb().definition },
                deathSettings: settings
            )
        )
        return (coordinator, world)
    }

    private static func kill(_ coordinator: RagdollCoordinator, _ world: FakeRagdollSessionWorld) {
        world.zeroHealth = [victim]
        _ = coordinator.advance(events: [], controls: RagdollGraphControls(), delta: 1 / 60)
    }

    @Test
    func meleeForceBlendsByDamageAndHoldsAtTheEnds() {
        let settings = DeathSettings.vanilla
        #expect(settings.melee.force(for: 1) == 4)
        #expect(settings.melee.force(for: 40) == 12)
        #expect(settings.melee.force(for: 500) == 12)
        #expect(settings.melee.force(for: -3) == 4)
        #expect(abs(settings.melee.force(for: 20.5) - 8) < 1e-4)
    }

    @Test
    func aSpellPushesAsARangedHitTimesItsMultiplier() {
        let settings = DeathSettings.vanilla
        let ranged = settings.force(of: CombatHitRecord(damage: 50, kind: .ranged))
        #expect(ranged == 30)
        #expect(settings.force(of: CombatHitRecord(damage: 50, kind: .spell)) == 60)
        #expect(settings.force(of: CombatHitRecord(damage: 50, kind: .other)) == 0)
    }

    @Test
    func aKillingHitPushesTheBodyAndDropsItsWeapon() {
        let (coordinator, world) = Self.session()
        world.dropsWeapon = true
        coordinator.noteHit(
            CombatHitRecord(damage: 40, kind: .melee, attacker: .player), on: Self.victim
        )
        Self.kill(coordinator, world)
        #expect(coordinator.deathEffects.pushedBodies == 1)
        #expect(coordinator.deathEffects.droppedWeapons == 1)
        #expect(coordinator.publishPoses().allSatisfy {
            if case .publishSeveredHeads = $0 {
                return false
            }
            return true
        }, "a dropped weapon leaves through a rebuild, not through a pose")
    }

    @Test
    func anOldHitDoesNotPush() {
        let (coordinator, world) = Self.session()
        coordinator.noteHit(
            CombatHitRecord(damage: 40, kind: .melee, attacker: .player), on: Self.victim
        )
        _ = coordinator.advance(events: [], controls: RagdollGraphControls(), delta: 3)
        Self.kill(coordinator, world)
        #expect(coordinator.deathEffects.pushedBodies == 0)
    }

    @Test
    func aSeveringBlowCutsTheHeadOnceAndKeepsTheCut() throws {
        var settings = DeathSettings.vanilla
        settings.dismemberChance = 100
        let (coordinator, world) = Self.session(settings: settings)
        world.severable = "NPC Head [Head]"
        world.animatedBones = ["NPC Head [Head]": MatrixMath.translation(SIMD3(100, 0, 120))]
        coordinator.noteHit(
            CombatHitRecord(damage: 40, kind: .melee, attacker: .player, canSever: true),
            on: Self.victim
        )
        Self.kill(coordinator, world)
        #expect(coordinator.deathEffects.dismemberments == 1)
        let head = try #require(coordinator.severedHeads[Self.victim])
        #expect(head.body.linearVelocity.x > 0, "the head flies away from the player at 0")
        #expect(head.body.linearVelocity.z > 0)
        #expect(world.dismemberments.map(\.1) == ["NPC Head [Head]"])
        let state = try #require(
            coordinator.store.component(ActorDeathState.self, for: Self.victim)
        )
        #expect(state.severedNode == "NPC Head [Head]")
        #expect(!coordinator.dismember(Self.victim), "a cut head stays cut")
    }

    @Test
    func aBlowThatCannotSeverLeavesTheHead() {
        var settings = DeathSettings.vanilla
        settings.dismemberChance = 100
        let (coordinator, world) = Self.session(settings: settings)
        world.severable = "NPC Head [Head]"
        coordinator.noteHit(CombatHitRecord(damage: 40, kind: .melee), on: Self.victim)
        Self.kill(coordinator, world)
        #expect(coordinator.deathEffects.dismemberments == 0)
    }

    @Test
    func theLivingCannotBeCut() {
        let (coordinator, world) = Self.session()
        world.severable = "NPC Head [Head]"
        #expect(!coordinator.dismember(Self.victim))
    }

    @Test
    func excessDeadRemovesTheOldestUnkeptBodiesOnceDeadLongEnough() {
        var settings = DeathSettings.vanilla
        settings.excessDeadCount = 1
        settings.excessDeadSeconds = 10
        let first = ReferenceKey.plugin(name: "skyrim.esm", objectID: 1)
        let second = ReferenceKey.plugin(name: "skyrim.esm", objectID: 2)
        let third = ReferenceKey.plugin(name: "skyrim.esm", objectID: 3)
        let dead = [(key: third, diedAt: Float(5)), (first, 0), (second, 1)]
        #expect(ExcessDeadRule.removals(
            dead: dead, kept: { _ in false }, now: 20, settings: settings
        ) == [first, second])
        #expect(ExcessDeadRule.removals(
            dead: dead, kept: { $0 == first }, now: 20, settings: settings
        ) == [second, third])
        #expect(ExcessDeadRule.removals(
            dead: dead, kept: { _ in false }, now: 10.5, settings: settings
        ) == [first], "the second has been dead only 9.5 s")
        settings.excessDeadCount = 3
        #expect(ExcessDeadRule.removals(
            dead: dead, kept: { _ in false }, now: 99, settings: settings
        ).isEmpty)
    }

    @Test
    func aCutHeadFallsAndPublishesItsOwnPose() throws {
        let (coordinator, world) = Self.session()
        world.severable = "NPC Head [Head]"
        world.animatedBones = ["NPC Head [Head]": MatrixMath.translation(SIMD3(100, 0, 120))]
        Self.kill(coordinator, world)
        #expect(coordinator.dismember(Self.victim))
        _ = coordinator.advance(events: [], controls: RagdollGraphControls(), delta: 0.1)
        let heads = coordinator.publishPoses().compactMap { command in
            if case let .publishSeveredHeads(poses) = command {
                return poses
            }
            return nil
        }
        let head = try #require(heads.first?[0x201]?["NPC Head [Head]"])
        #expect(head.columns.3.z < 120 + SeveredHead.launchLift * 0.1)
        #expect(head.columns.3.z != 120, "the head moved")
    }

    @Test
    func aHeadAtTheCutDrawsWhereItWas() throws {
        let place = MatrixMath.translation(SIMD3(5, 0, 0))
        let neck = MatrixMath.translation(SIMD3(0, 0, 110))
        let pose = ["NPC Head [Head]": MatrixMath.translation(SIMD3(0, 0, 120)), "Neck": neck]
        let head = try #require(SeveredHead(
            key: Self.victim, cell: FakeRagdollSessionWorld.cell, node: "NPC Head [Head]",
            pose: pose, actorToWorld: place, away: nil
        ))
        let drawn = try #require(head.bonePose(actorToWorld: place)["Neck"])
        #expect(simd_almost_equal_elements(drawn, neck, 1e-4))
        #expect(head.body.linearVelocity == .zero, "a head with no blow only drops")
    }

    @Test
    func aDroppedHeadComesToRestOnTheFloor() throws {
        let floor = DynamicStepWorld(
            staticCandidates: DynamicBodyScene.query([DynamicBodyScene.floor()])
        )
        var head = try #require(SeveredHead(
            key: Self.victim, cell: FakeRagdollSessionWorld.cell, node: "NPC Head [Head]",
            pose: ["NPC Head [Head]": MatrixMath.translation(SIMD3(0, 0, 120))],
            actorToWorld: matrix_identity_float4x4, away: .zero
        ))
        for _ in 0 ..< 300 {
            head.advance(by: 1 / 60, world: floor)
        }
        #expect(head.body.isSleeping, "a sphere in its contact margin keeps the floor")
        #expect(abs(head.body.position.z - SeveredHead.radius) < 2)
    }

    @Test
    func aHeadCutFromAFallenBodyStartsAtItsDrawnNeck() throws {
        let (coordinator, world) = Self.session()
        world.severable = "Bone2"
        world.animatedBones = Dictionary(uniqueKeysWithValues: (0 ..< 3).map {
            ("Bone\($0)", MatrixMath.translation(SIMD3(Float($0) * 24, 0, 120)))
        })
        Self.kill(coordinator, world)
        for _ in 0 ..< 30 {
            _ = coordinator.advance(events: [], controls: RagdollGraphControls(), delta: 1 / 60)
        }
        let published = coordinator.publishPoses().compactMap { command -> float4x4? in
            guard case let .publishPoses(poses) = command else { return nil }
            return poses[0x201]?["Bone2"]
        }
        let drawn = try #require(published.first)

        #expect(coordinator.dismember(Self.victim))

        let head = try #require(coordinator.severedHeads[Self.victim])
        let start = SIMD3(drawn.columns.3.x, drawn.columns.3.y, drawn.columns.3.z)
        #expect(simd_distance(head.body.position, start) < 1, "not the standing pose at 120")
    }

    @Test
    func aHeadKeepsFlyingThroughAFrameItsBodyHasNoPose() throws {
        let (coordinator, world) = Self.session()
        world.severable = "NPC Head [Head]"
        world.animatedBones = ["NPC Head [Head]": MatrixMath.translation(SIMD3(100, 0, 120))]
        Self.kill(coordinator, world)
        #expect(coordinator.dismember(Self.victim))
        let residents = world.ragdollResidents

        world.ragdollResidents = []
        _ = coordinator.publishPoses()
        world.ragdollResidents = residents
        _ = coordinator.publishPoses()

        let head = try #require(coordinator.severedHeads[Self.victim])
        #expect(head.body.linearVelocity.z > 0, "the same head, not one dropped anew")
    }
}
