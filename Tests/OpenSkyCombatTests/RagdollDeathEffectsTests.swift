// The death effects against a fake world: the push of the killing hit, the weapon
// drop, the head cut, the excess-dead rule, and the node hiding of a cut.

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
    private static let other = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x202)

    private static func session(
        settings: DeathSettings = .vanilla
    ) -> (RagdollCoordinator, FakeRagdollSessionWorld) {
        let world = FakeRagdollSessionWorld()
        world.ragdollResidents = [RagdollResident(key: victim, position: SIMD3(100, 0, 0))]
        let coordinator = RagdollCoordinator(store: WorldStateStore(), world: world)
        coordinator.wire(loadDefinition: { _, _, _ in RagdollFixture.limb().definition })
        coordinator.deathSettings = settings
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
        world.droppedWeaponNodes = ["Weapon", "WeaponSword"]
        coordinator.noteHit(
            CombatHitRecord(damage: 40, kind: .melee, attacker: .player), on: Self.victim
        )
        Self.kill(coordinator, world)
        #expect(coordinator.deathEffects.pushedBodies == 1)
        #expect(coordinator.deathEffects.droppedWeapons == 1)
        #expect(coordinator.hiddenNodesByResident()[Self.victim] == ["Weapon", "WeaponSword"])
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
        coordinator.noteHit(
            CombatHitRecord(damage: 40, kind: .melee, attacker: .player, canSever: true),
            on: Self.victim
        )
        Self.kill(coordinator, world)
        #expect(coordinator.deathEffects.dismemberments == 1)
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
    func hidingANodeCollapsesItAndEveryBoneUnderIt() {
        let pose: [String: float4x4] = [
            "root": matrix_identity_float4x4,
            "neck": MatrixMath.translation(SIMD3(0, 0, 100)),
            "head": MatrixMath.translation(SIMD3(0, 0, 110)),
            "jaw": MatrixMath.translation(SIMD3(0, 5, 108))
        ]
        let collapsed = PoseNodeHiding.collapsed(
            ["head"], names: ["root", "neck", "head", "jaw"], parents: [-1, 0, 1, 2], pose: pose
        )
        #expect(Set(collapsed.keys) == ["head", "jaw"])
        let jaw = collapsed["jaw"]
        #expect(jaw?.columns.0 == .zero)
        #expect(jaw?.columns.3 == SIMD4(0, 0, 110, 1), "the jaw folds into the head's origin")
    }
}
