// Walk-mode targeting and engine-owned activation events over synthetic
// streamed scenes. A nil interaction ray represents fly mode.

@testable import opensky
import simd
import Testing

extension CellStreamerTests {
    @Test
    func viewRayPublishesTargetAndGenericActivationEvent() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner, radius: 0)
        var targets: [InteractionTarget?] = []
        var events: [InteractionEvent] = []
        streamer.onInteractionTargetChanged = { targets.append($0) }
        streamer.onInteraction.add { events.append($0) }

        streamer.update(cameraPosition: Self.center)
        let position = Self.center + SIMD3<Float>(10, 0, 0)
        let interaction = Self.interaction(
            reference: 0x21,
            position: position,
            action: .activate,
            name: "Test Lever",
            actionLabel: "Pull"
        )
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(
            location: .exterior(Self.coordinate(0, 0)),
            interactions: [interaction.reference: interaction],
            staticCollision: Self.collision(reference: 0x21, position: position)
        )))
        let ray = Self.interactionRay(from: Self.center, to: position)
        streamer.update(cameraPosition: Self.center, interactionRay: ray)

        #expect(streamer.interactionTarget?.interaction == interaction)
        #expect(targets.last.flatMap(\.self)?.interaction == interaction)

        streamer.update(
            cameraPosition: Self.center,
            interactionRay: ray,
            activate: true
        )
        #expect(events.count == 1)
        #expect(events.first?.target.interaction == interaction)
        #expect(runner.enqueuedDoorTransitions.isEmpty)

        streamer.update(cameraPosition: Self.center, activate: true)
        #expect(streamer.interactionTarget == nil)
        #expect(events.count == 1)
    }

    @Test
    func nonInteractiveCollisionOccludesTargetBehindIt() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner, radius: 0)
        streamer.update(cameraPosition: Self.center)

        let blockerPosition = Self.center + SIMD3<Float>(10, 0, 0)
        let targetPosition = Self.center + SIMD3<Float>(20, 0, 0)
        let target = Self.interaction(
            reference: 0x32,
            position: targetPosition,
            action: .search,
            name: "Test Chest",
            actionLabel: "Search"
        )
        let collision = Self.collisionSet(shapes: [
            Self.collisionShape(reference: 0x31, position: blockerPosition),
            Self.collisionShape(reference: 0x32, position: targetPosition)
        ])
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(
            location: .exterior(Self.coordinate(0, 0)),
            interactions: [target.reference: target],
            staticCollision: collision
        )))
        streamer.update(
            cameraPosition: Self.center,
            interactionRay: Self.interactionRay(from: Self.center, to: targetPosition)
        )

        #expect(streamer.interactionTarget == nil)
    }
}
