// The Face Morphs panel shell: it acts on the playback of the selected actor only.

@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import Testing

@MainActor
struct FaceMorphCoordinatorTests {
    private final class World: FaceMorphWorld {
        var faceMorphSubject: FormID?
        let playback = FaceMorphPlayback(
            actor: FormID(0x1A67), bindings: [:], pairedPaths: ["head.tri"], misses: [
                FaceMorphAssociationMiss(headPart: FormID(0x51), reason: "no TRI")
            ]
        )

        func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback? {
            actor == playback.actor ? playback : nil
        }
    }

    @Test
    func noSubjectGivesTheEmptySnapshot() {
        let world = World()
        let coordinator = FaceMorphCoordinator()
        coordinator.attach(world: world)
        #expect(coordinator.faceMorphSnapshot == .empty)
        world.faceMorphSubject = FormID(0x99)
        #expect(coordinator.faceMorphSnapshot == .empty)
    }

    @Test
    func theSubjectsPlaybackIsReadAndWritten() {
        let world = World()
        world.faceMorphSubject = world.playback.actor
        let coordinator = FaceMorphCoordinator()
        coordinator.attach(world: world)
        coordinator.setFaceMorphWeight(0.5, target: "Aah")
        let snapshot = coordinator.faceMorphSnapshot
        #expect(snapshot.actor == world.playback.actor)
        #expect(snapshot.pairedPaths == ["head.tri"])
        #expect(snapshot.associationMisses == ["\(FormID(0x51)): no TRI"])
        #expect(snapshot.unknownTargetCount == 1)
    }
}
