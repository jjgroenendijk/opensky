// The coordinator turns clip annotations into calls on its world port: sounds at
// the source, camera shake from the source, and head tracking holds.

@testable import OpenSkyBehavior
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import simd
import Testing

private struct PlayedSound {
    let editorID: String
    let position: SIMD3<Float>
}

@MainActor
private final class FakeAnimationEventWorld: AnimationEventWorld {
    var positions: [ReferenceKey: SIMD3<Float>] = [:]
    var knownSounds: Set<String> = []
    var played: [PlayedSound] = []
    var stopped: [(String, ReferenceKey)] = []
    var shakes: [(SIMD3<Float>, Float)] = []
    var headTracking: [(Bool, ReferenceKey)] = []

    func animationEventPosition(of source: ReferenceKey) -> SIMD3<Float>? {
        positions[source]
    }

    func playAnimationSound(
        editorID: String, source: ReferenceKey, at position: SIMD3<Float>
    ) -> Bool {
        played.append(PlayedSound(editorID: editorID, position: position))
        return knownSounds.contains(editorID)
    }

    func stopAnimationSound(editorID: String, source: ReferenceKey) {
        stopped.append((editorID, source))
    }

    func shakeCamera(from position: SIMD3<Float>, strength: Float) {
        shakes.append((position, strength))
    }

    func setHeadTracking(_ enabled: Bool, for actor: ReferenceKey) {
        headTracking.append((enabled, actor))
    }
}

@MainActor
struct AnimationEventCoordinatorTests {
    private let actor = ReferenceKey.plugin(name: "test.esp", objectID: 0x10)

    private func make() -> (AnimationEventCoordinator, FakeAnimationEventWorld) {
        let world = FakeAnimationEventWorld()
        world.positions = [actor: SIMD3(1, 2, 3), .player: SIMD3(0, 0, 0)]
        world.knownSounds = ["TestClap"]
        let coordinator = AnimationEventCoordinator()
        coordinator.attach(world: world)
        return (coordinator, world)
    }

    @Test func aSoundPlaysWhereTheSourceStands() {
        let (coordinator, world) = make()
        coordinator.handle("SoundPlay.TestClap", from: actor)
        #expect(world.played.count == 1)
        #expect(world.played.first?.editorID == "TestClap")
        #expect(world.played.first?.position == SIMD3(1, 2, 3))
        #expect(coordinator.missingSounds.isEmpty)
        #expect(coordinator.readout == ["sound play: 1"])
    }

    @Test func aSoundNoRecordHasIsListed() {
        let (coordinator, world) = make()
        coordinator.handle("SoundPlay.TestMissing", from: actor)
        #expect(coordinator.missingSounds == ["TestMissing"])
        #expect(world.played.count == 1)
    }

    @Test func anUnloadedSourceIsSilent() {
        let (coordinator, world) = make()
        let gone = ReferenceKey.plugin(name: "test.esp", objectID: 0x99)
        #expect(coordinator.handle("SoundPlay.TestClap", from: gone) == nil)
        #expect(world.played.isEmpty)
    }

    @Test func stopShakeAndHeadTrackingReachTheWorld() {
        let (coordinator, world) = make()
        coordinator.handle("SoundStop.TestLoop", from: actor)
        coordinator.handle("CameraShake.0.5", from: actor)
        coordinator.handle("HeadTrackingOff", from: actor)
        #expect(world.stopped.first?.0 == "TestLoop")
        #expect(world.shakes.first?.0 == SIMD3(1, 2, 3))
        #expect(world.shakes.first?.1 == 0.5)
        #expect(world.headTracking.first?.0 == false)
        #expect(coordinator.lastEvent?.hasPrefix("HeadTrackingOff") == true)
    }

    @Test func offOrAGraphEventDoesNothing() {
        let (coordinator, world) = make()
        #expect(coordinator.handle("FootLeft", from: actor) == nil)
        coordinator.isEnabled = false
        #expect(coordinator.handle("SoundPlay.TestClap", from: actor) == nil)
        #expect(world.played.isEmpty)
        #expect(coordinator.counts.isEmpty)
    }

    @Test func headTrackingOffHoldsTheActorUntilOn() {
        let tracking = HeadTrackingCoordinator()
        tracking.setHeadTracking(false, for: actor)
        #expect(tracking.heldForward == [actor])
        tracking.setHeadTracking(true, for: actor)
        #expect(tracking.heldForward.isEmpty)
    }
}
