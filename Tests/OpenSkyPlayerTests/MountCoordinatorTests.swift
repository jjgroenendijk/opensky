// The mount and dismount phases, the steal question, and the commands the app applies.

import OpenSkyActorPresentation
@testable import OpenSkyBehavior
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyPhysics
@testable import OpenSkyPlayer
import OpenSkyRendering
import simd
import Testing

@MainActor
private final class FakeMountWorld: MountWorld {
    var candidates: [ReferenceKey: MountCandidate] = [:]
    var taken: [ReferenceKey] = []

    func mountCandidate(_ key: ReferenceKey) -> MountCandidate? {
        candidates[key]
    }

    func takeMount(_ key: ReferenceKey, kind: MountKind, saddleBone: String)
        -> PlayerMountDriveStart?
    {
        taken.append(key)
        return PlayerMountDriveStart(
            mount: key, kind: kind, saddleBone: saddleBone, feet: SIMD3(0, 0, 0), yaw: 0,
            graph: nil, pose: PlayerPoseBuffer(), configuration: .synthetic
        )
    }

    func dismountOffset(of _: ReferenceKey) -> SIMD3<Float> {
        SIMD3(-50, 0, 65)
    }
}

@MainActor
struct MountCoordinatorTests {
    private static let horse = ReferenceKey.generated(100)
    private static let flat = MountStepWorld(
        sampleGround: { _ in nil }, collisionQuery: { _ in [] }
    )

    private func world(ownership: MountOwnership = .free) -> FakeMountWorld {
        let world = FakeMountWorld()
        var candidate = MountCandidate(key: Self.horse)
        candidate.saddleBone = "SaddleBone"
        candidate.ownership = ownership
        world.candidates[Self.horse] = candidate
        return world
    }

    @Test func mountingPlaysThePairedClipThenSeatsTheRider() {
        let world = world()
        let mounts = MountCoordinator(world: world)
        #expect(
            mounts.mount(Self.horse) == [.boardPlayer(Self.horse), .raiseOnPlayer("HorseEnter")]
        )
        #expect(mounts.phase == .mounting(elapsed: 0))
        #expect(mounts.drive?.isSteerable == false)
        #expect(mounts.handleRiderEvents(["pairedStop"])
            == [.seatPlayer(Self.horse, bone: "SaddleBone")])
        #expect(mounts.phase == .riding)
        #expect(mounts.drive?.isSteerable == true)
        #expect(mounts.mount(Self.horse) == [.refused(.alreadyRiding)])
    }

    @Test func dismountingEndsOnTheExitEventBesideTheMount() {
        let world = world()
        let mounts = MountCoordinator(world: world)
        _ = mounts.mount(Self.horse)
        _ = mounts.handleRiderEvents(["pairedStop"])
        #expect(
            mounts.dismount() == [.boardPlayer(Self.horse), .raiseOnPlayer("HorseExit")]
        )
        let done = mounts.handleRiderEvents(["HorseExitOut"])
        #expect(done.first == .detachPlayer)
        #expect(done.last == .releaseMount(Self.horse))
        guard done.count == 3, case let .placePlayer(feet, _) = done[1] else {
            Issue.record("no place command")
            return
        }
        #expect(abs(feet.y - 50) < 0.001)
        #expect(!mounts.isActive)
        #expect(mounts.lastMount == Self.horse)
    }

    @Test func aPhaseWithoutItsEventEndsOnTheTimeout() {
        let world = world()
        let mounts = MountCoordinator(world: world)
        _ = mounts.mount(Self.horse)
        let commands = mounts.advance(
            input: CameraInput(dt: 0.1), cameraYaw: 0, weaponDrawn: false, world: Self.flat
        )
        guard case let .steerMount(key, _, yaw) = commands.first else {
            Issue.record("no steer command")
            return
        }
        #expect(key == Self.horse && yaw == 0)
        for _ in 0 ..< 40 {
            _ = mounts.advance(
                input: CameraInput(dt: 0.1), cameraYaw: 0, weaponDrawn: false, world: Self.flat
            )
        }
        #expect(mounts.phase == .riding)
    }

    @Test func anOwnedHorseAsksFirstAndIsATheft() {
        let world = world(ownership: .other)
        let mounts = MountCoordinator(world: world)
        #expect(mounts.mount(Self.horse) == [.askToSteal(Self.horse)])
        #expect(!mounts.isActive)
        #expect(mounts.mount(Self.horse, stealConfirmed: true).last
            == .reportTheft(Self.horse))
    }

    @Test func aDeadMountDropsTheRider() {
        let world = world()
        let mounts = MountCoordinator(world: world)
        _ = mounts.mount(Self.horse)
        world.candidates[Self.horse]?.isDead = true
        let commands = mounts.advance(
            input: CameraInput(dt: 0.1), cameraYaw: 0, weaponDrawn: false, world: Self.flat
        )
        #expect(commands.last == .releaseMount(Self.horse))
        #expect(mounts.phase == .none)
    }

    @Test func theRiderGraphReadsTheHorseStateAndTheStance() {
        var table = BehaviorObjectTable()
        let root = table.add(
            BehaviorFixture.clipGenerator("idle", animationName: "idle"), at: 0x10
        )
        let graph = BehaviorFixture.instance(root: root, table: table)
        let bridge = LocomotionBridge(configuration: .synthetic, graph: graph)
        bridge.actorState.weaponDrawn = true
        bridge.advanceRiding(
            deltaTime: 0.1, feet: SIMD3(0, 0, 0), yaw: 0,
            mount: MountMotion(speed: 300, turnDelta: 0, isSprinting: true)
        )
        #expect(bridge.actorState.riding == .sprinting)
        #expect(ActorStateGraphCore.state(for: bridge.actorState, gait: .run) == .horseSprint)
        #expect(bridge.status.missingEvents.contains("combatStanceStart"))
        #expect(bridge.status.missingEvents.contains("moveStart"))
        bridge.actorState.riding = .riding
        #expect(ActorStateGraphCore.state(for: bridge.actorState, gait: .run) == .npcHorse)
    }
}
