// The bodies the camera fade sweeps against: the living actors near the player, each with
// its posed ragdoll bones or else its movement capsule.

@testable import OpenSkyActorAdapters
import OpenSkyCombatInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkySessionTesting
import OpenSkyWorldInterface
import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@MainActor
struct ActorCameraBodiesAdapterTests {
    private let host = ActorHost()
    private let session = FakeGameSessionPort()
    private let adapter: ActorCameraBodiesAdapter
    private static let npc = ReferenceKey.generated(3)
    private static let formID: UInt32 = 0x1234

    init() throws {
        session.movementModeValue = .thirdPerson
        session.freeFlyCameraValue = FreeFlyCamera(position: SIMD3(0, -150, 120), yaw: 0, pitch: 0)
        host.gameSession = session
        host.fakeStreamer.referenceEntryKeyResult = try RuntimeReferenceEntry(
            key: Self.npc, formID: FormID(Self.formID), isPersistent: false,
            record: .actor(placedActor(position: SIMD3(0, -80, 0)))
        )
        adapter = ActorCameraBodiesAdapter(game: host, stage: nil)
    }

    @Test func anActorWithoutARagdollPublishesItsCapsule() {
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.npc, feet: SIMD3(0, -80, 0)),
            CombatActorObservation(key: .player, feet: .zero),
            CombatActorObservation(key: .generated(4), feet: SIMD3(40, 0, 0), isDead: true),
            CombatActorObservation(key: .generated(5), feet: SIMD3(5000, 0, 0))
        ]
        adapter.publish()
        let capsule = PlayerCapsule.standard
        #expect(session.actorCameraBodies == [ActorCameraFade.Candidate(
            formID: Self.formID,
            bodies: [ActorCameraFade.Body(
                start: SIMD3(0, -80, capsule.radius),
                end: SIMD3(0, -80, max(capsule.height - capsule.radius, capsule.radius)),
                radius: capsule.radius, boundRadius: capsule.centreHeight
            )]
        )])
    }

    @Test func theRiddenMountIsLeftOut() {
        host.fakeMountWorld.riddenMount = Self.npc
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.npc, feet: SIMD3(0, -80, 0))
        ]
        adapter.publish()
        #expect(session.actorCameraBodies.isEmpty)
    }

    @Test func aPosedRagdollPublishesItsBones() {
        let spine = "NPC Spine [Spn0]"
        host.fakeRagdoll.ragdollDefinitionResult = RagdollDefinition(bones: [
            RagdollBoneDefinition(
                boneName: spine, boneIndex: 0,
                body: DynamicBodyDefinition(
                    volumes: [.radial(first: SIMD3(0, 0, -10), second: SIMD3(0, 0, 10), radius: 6)],
                    mass: 4
                ),
                bindBoneMatrix: matrix_identity_float4x4
            )
        ], joints: [])
        host.poses[Self.npc] = [spine: MatrixMath.translation(SIMD3(0, 0, 60))]
        host.fakeActorWorld.combatActorsResult = [
            CombatActorObservation(key: Self.npc, feet: SIMD3(0, -80, 0))
        ]
        adapter.publish()
        let bodies = session.actorCameraBodies.first?.bodies ?? []
        #expect(bodies.count == 1)
        #expect(bodies.first?.radius == 6)
    }

    @Test func aFreeCameraPublishesNothing() {
        session.actorCameraBodies = [ActorCameraFade.Candidate(formID: 1, bodies: [])]
        session.movementModeValue = .fly
        adapter.publish()
        #expect(session.actorCameraBodies.isEmpty)
    }
}
