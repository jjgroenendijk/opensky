// A living actor knocked down: the phases, the push by limb, the get-up facing, and the
// ragdoll coordinator's knockdown path against a fake world (docs/engine/ragdoll.md#knockdown).

@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
@testable import OpenSkyWorldState
import simd
import Testing

@MainActor
struct KnockdownTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x101)

    @Test func aDownActorGetsUpOnceStillAndStandsAfterTheBlend() {
        var tracker = KnockdownTracker()
        tracker.knockDown(Self.actor, downTime: 15)
        let moving = tracker.advance(by: 1, getUpDuration: { _ in 2 }, isStill: { _ in false })
        #expect(moving == KnockdownStep())
        #expect(tracker.phases[Self.actor] == .down(remaining: 14))
        let still = tracker.advance(by: 1, getUpDuration: { _ in 2 }, isStill: { _ in true })
        #expect(still.gettingUp == [Self.actor])
        _ = tracker.advance(by: 1, getUpDuration: { _ in 2 }, isStill: { _ in true })
        #expect(tracker.ragdollWeight(of: Self.actor) == 0.5)
        let stood = tracker.advance(by: 1, getUpDuration: { _ in 2 }, isStill: { _ in true })
        #expect(stood.stood == [Self.actor])
        #expect(!tracker.isKnockedDown(Self.actor))
    }

    @Test func aDownActorGetsUpWhenItsTimeRunsOut() {
        var tracker = KnockdownTracker()
        tracker.knockDown(Self.actor, downTime: 15)
        #expect(tracker.ragdollWeight(of: Self.actor) == 1)
        let step = tracker.advance(by: 15, getUpDuration: { _ in 1 }, isStill: { _ in false })
        #expect(step.gettingUp == [Self.actor])
    }

    @Test func eachLimbTakesItsShareOfTheKnock() {
        #expect(KnockdownPush.weight(ofBone: "NPC Spine1 [Spn1]") == 1)
        #expect(KnockdownPush.weight(ofBone: "NPC Head [Head]") == 1)
        #expect(KnockdownPush.weight(ofBone: "NPC L UpperArm [LUar]") == 0.75)
        #expect(KnockdownPush.weight(ofBone: "NPC R Thigh [RThg]") == 0.75)
        #expect(KnockdownPush.weight(ofBone: "NPC L Forearm [LLar]") == 0.5)
        #expect(KnockdownPush.weight(ofBone: "NPC R Calf [RClf]") == 0.5)
        #expect(KnockdownPush.weight(ofBone: "NPC L Hand [LHnd]") == 0.25)
        #expect(KnockdownPush.weight(ofBone: "NPC R Foot [Rft ]") == 0.25)
    }

    @Test func anActorGetsUpFacingFromItsPelvisToItsNeck() throws {
        let yaw = try #require(KnockdownPush.getUpYaw(pelvis: .zero, neck: SIMD3(0, 50, -3)))
        #expect(abs(yaw - .pi / 2) < 0.0001)
        #expect(KnockdownPush.getUpYaw(pelvis: .zero, neck: SIMD3(0, 0, 50)) == nil)
    }

    @Test func aKnockPushesEachBodyAwayByItsShare() {
        var instance = RagdollFixture.limb(origin: SIMD3(100, 0, 0), kick: 0)
        instance.push(awayFrom: .zero, speed: 700) { $0 == "Bone2" ? 0.5 : 1 }
        #expect(abs(instance.bodies[0].linearVelocity.x - 700) < 0.01)
        #expect(abs(instance.bodies[2].linearVelocity.x - 350) < 0.01)
        #expect(!instance.isStillEnoughToGetUp)
    }

    @Test func aLivingActorIsKnockedDownAndGetsUp() throws {
        let world = FakeRagdollSessionWorld()
        world.ragdollResidents = [RagdollResident(key: Self.actor, position: SIMD3(100, 0, 0))]
        let coordinator = RagdollCoordinator(
            store: WorldStateStore(), world: world,
            data: RagdollSessionData(loadDefinition: { _, _, _ in
                RagdollFixture.limb().definition
            })
        )
        #expect(coordinator.knockDown(Self.actor, from: .zero, magnitude: 10, downTime: 15))
        let runtime = try #require(coordinator.runtime)
        #expect(runtime.world.isRagdolling(Self.actor))
        let controls = RagdollGraphControls()
        let entered = coordinator.advance(events: [], controls: controls, delta: 1 / 60)
        #expect(entered.contains(.enterKnockdown(Self.actor)))
        let getUp = coordinator.advance(events: [], controls: controls, delta: 15)
        #expect(getUp.contains {
            if case .getUp(Self.actor, _, _) = $0 {
                true
            } else {
                false
            }
        })
        let stood = coordinator.advance(events: [], controls: controls, delta: 2)
        #expect(stood.contains(.endKnockdown(Self.actor)))
        #expect(!runtime.world.isRagdolling(Self.actor))
        #expect(coordinator.deathState(of: Self.actor) == nil)
    }

    @Test func aDeadActorIsNotKnockedDown() {
        let world = FakeRagdollSessionWorld()
        world.ragdollResidents = [RagdollResident(key: Self.actor, position: .zero)]
        world.zeroHealth = [Self.actor]
        let coordinator = RagdollCoordinator(
            store: WorldStateStore(), world: world,
            data: RagdollSessionData(loadDefinition: { _, _, _ in
                RagdollFixture.limb().definition
            })
        )
        _ = coordinator.advance(events: [], controls: RagdollGraphControls(), delta: 1 / 60)
        #expect(!coordinator.knockDown(Self.actor, from: .zero, magnitude: 10, downTime: 15))
    }

    @Test func theLivingPlayerIsKnockedDownButNotTheDeadPlayer() {
        let world = FakeRagdollSessionWorld()
        world.playerHasBody = true
        let coordinator = RagdollCoordinator(
            store: WorldStateStore(), world: world,
            data: RagdollSessionData(loadDefinition: { _, _, _ in
                RagdollFixture.limb().definition
            })
        )
        #expect(coordinator.knockDown(.player, from: .zero, magnitude: 5, downTime: 15))
        #expect(coordinator.knockdowns.isKnockedDown(.player))
        _ = coordinator.advancePlayerDeath(
            by: 1, health: PlayerHealthSample(share: 0, isEssential: false, bleedoutRatio: nil)
        )
        _ = coordinator.advance(events: [], controls: RagdollGraphControls(), delta: 1 / 60)
        #expect(!coordinator.knockdowns.isKnockedDown(.player))
        #expect(!coordinator.knockDown(.player, from: .zero, magnitude: 5, downTime: 15))
    }
}
