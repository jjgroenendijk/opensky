// Walk-mode targeting and engine-owned activation events over synthetic
// streamed scenes. A nil interaction ray represents fly mode.

@testable import OpenSkyGameData
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldInterface
import OpenSkyWorldTesting
import simd
import Testing

private typealias Fixture = CellStreamerFixture

extension CellStreamerTests {
    @Test
    func viewRayPublishesTargetAndGenericActivationEvent() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner, radius: 0)
        var targets: [InteractionTarget?] = []
        var events: [InteractionEvent] = []
        streamer.onInteractionTargetChanged = { targets.append($0) }
        streamer.onInteraction.add { events.append($0) }

        streamer.update(cameraPosition: Fixture.center)
        let position = Fixture.center + SIMD3<Float>(10, 0, 0)
        let interaction = Fixture.interaction(
            reference: 0x21,
            position: position,
            action: .activate,
            name: "Test Lever",
            actionLabel: "Pull"
        )
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene(
            location: .exterior(Fixture.coordinate(0, 0)),
            interactions: [interaction.reference: interaction],
            staticCollision: Fixture.collision(reference: 0x21, position: position)
        )))
        let ray = Fixture.interactionRay(from: Fixture.center, to: position)
        streamer.update(cameraPosition: Fixture.center, interactionRay: ray)

        #expect(streamer.interactionTarget?.interaction == interaction)
        #expect(targets.last.flatMap(\.self)?.interaction == interaction)

        streamer.update(
            cameraPosition: Fixture.center,
            interactionRay: ray,
            activate: true
        )
        #expect(events.count == 1)
        #expect(events.first?.target.interaction == interaction)
        #expect(runner.enqueuedDoorTransitions.isEmpty)

        streamer.update(cameraPosition: Fixture.center, activate: true)
        #expect(streamer.interactionTarget == nil)
        #expect(events.count == 1)
    }

    @Test
    func nonInteractiveCollisionOccludesTargetBehindIt() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner, radius: 0)
        streamer.update(cameraPosition: Fixture.center)

        let blockerPosition = Fixture.center + SIMD3<Float>(10, 0, 0)
        let targetPosition = Fixture.center + SIMD3<Float>(20, 0, 0)
        let target = Fixture.interaction(
            reference: 0x32,
            position: targetPosition,
            action: .search,
            name: "Test Chest",
            actionLabel: "Search"
        )
        let collision = Fixture.collisionSet(shapes: [
            Fixture.collisionShape(reference: 0x31, position: blockerPosition),
            Fixture.collisionShape(reference: 0x32, position: targetPosition)
        ])
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene(
            location: .exterior(Fixture.coordinate(0, 0)),
            interactions: [target.reference: target],
            staticCollision: collision
        )))
        streamer.update(
            cameraPosition: Fixture.center,
            interactionRay: Fixture.interactionRay(from: Fixture.center, to: targetPosition)
        )

        #expect(streamer.interactionTarget == nil)
    }
}
