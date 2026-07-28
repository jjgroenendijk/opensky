// Proximity door activation + interior streaming suspension/resume.

@testable import opensky
import simd
import Testing

extension CellStreamerTests {
    @Test
    func playerDoorTransitionPublishesMotionAndCloseBoundaries() {
        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner, radius: 0)
        var phases: [InteractionAnimationPhase] = []
        streamer.onInteractionAnimation = { phases.append($0.phase) }
        streamer.update(cameraPosition: Self.center)
        let door = Self.door(reference: 0x10, destination: 0x20, position: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.interactiveScene(
            location: .exterior(Self.coordinate(0, 0)),
            door: door,
            sounds: ModelBase.Sounds(
                activation: FormID(0xA01),
                close: FormID(0xA02),
                loop: FormID(0xA03)
            )
        )))
        streamer.update(cameraPosition: Self.center)

        let usePosition = Self.center - SIMD3<Float>(10, 0, 0)
        Self.activate(streamer, from: usePosition, toward: Self.center)
        #expect(phases == [.motionStarted])

        runner.completeDoorTransition(from: FormID(0x10), with: .success(DoorTransition(
            sourceDoor: FormID(0x10),
            destinationDoor: FormID(0x20),
            destinationPlacement: PlacedReference.Placement(
                position: Self.center, rotation: .zero
            ),
            scene: Self.cellScene(location: .interior(FormID(0x138CA)))
        )))
        streamer.update(cameraPosition: Self.center)

        #expect(phases == [.motionStarted, .closed])
    }

    @Test
    func failedPlayerDoorTransitionCancelsMotion() {
        enum DoorFailure: Error { case broken }

        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner, radius: 0)
        var phases: [InteractionAnimationPhase] = []
        streamer.onInteractionAnimation = { phases.append($0.phase) }
        streamer.update(cameraPosition: Self.center)
        let door = Self.door(reference: 0x10, destination: 0x20, position: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.interactiveScene(
            location: .exterior(Self.coordinate(0, 0)), door: door
        )))
        streamer.update(cameraPosition: Self.center)

        let usePosition = Self.center - SIMD3<Float>(10, 0, 0)
        Self.activate(streamer, from: usePosition, toward: Self.center)
        runner.completeDoorTransition(from: FormID(0x10), with: .failure(DoorFailure.broken))
        streamer.update(cameraPosition: Self.center)

        #expect(phases == [.motionStarted, .cancelled])
    }

    @Test
    func failedDoorTransitionIsCountedForAcceptance() {
        enum DoorFailure: Error { case broken }

        let runner = ManualCellBuildRunner()
        let streamer = Self.makeStreamer(runner: runner, radius: 0)
        streamer.update(cameraPosition: Self.center)
        let outside = Self.door(reference: 0x10, destination: 0x20, position: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.interactiveScene(
            location: .exterior(Self.coordinate(0, 0)), door: outside
        )))
        streamer.update(cameraPosition: Self.center)
        let usePosition = Self.center - SIMD3<Float>(10, 0, 0)
        Self.activate(streamer, from: usePosition, toward: Self.center)
        runner.completeDoorTransition(from: FormID(0x10), with: .failure(DoorFailure.broken))
        streamer.update(cameraPosition: Self.center)

        #expect(streamer.doorTransitionFailureCount == 1)
        #expect(!streamer.isInterior)
    }

    @Test
    func selectedDoorEntersInteriorSuspendsGridThenReturns() {
        let runner = ManualCellBuildRunner()
        var cameras: [SceneCamera?] = []
        let streamer = Self.makeStreamer(runner: runner, radius: 0) { _, camera in
            cameras.append(camera)
        }
        streamer.update(cameraPosition: Self.center)
        let outside = Self.door(reference: 0x10, destination: 0x20, position: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.interactiveScene(
            location: .exterior(Self.coordinate(0, 0)), door: outside
        )))
        streamer.update(cameraPosition: Self.center)

        let farPosition = Self.center + SIMD3<Float>(500, 0, 0)
        Self.activate(streamer, from: farPosition, toward: Self.center)
        #expect(runner.enqueuedDoorTransitions.isEmpty)
        let outsideUsePosition = Self.center - SIMD3<Float>(10, 0, 0)
        Self.activate(streamer, from: outsideUsePosition, toward: Self.center)
        #expect(runner.enqueuedDoorTransitions == [FormID(0x10)])

        let insidePosition = SIMD3<Float>(100, 200, 300)
        let inside = Self.door(reference: 0x20, destination: 0x10, position: insidePosition)
        let interior = Self.interactiveScene(
            location: .interior(FormID(0x138CA)), door: inside
        )
        runner.completeDoorTransition(from: FormID(0x10), with: .success(DoorTransition(
            sourceDoor: FormID(0x10),
            destinationDoor: FormID(0x20),
            destinationPlacement: PlacedReference.Placement(
                position: insidePosition, rotation: SIMD3(0.1, 0, 0.5)
            ),
            scene: interior
        )))
        streamer.update(cameraPosition: Self.center)
        #expect(streamer.isInterior)
        #expect(cameras.last.flatMap(\.self)?.eye == insidePosition)

        let exteriorBuildCount = runner.enqueued.count
        streamer.update(cameraPosition: CellGridManager.cellCenter(of: Self.coordinate(20, 20)))
        #expect(runner.enqueued.count == exteriorBuildCount)

        let insideUsePosition = insidePosition - SIMD3<Float>(10, 0, 0)
        Self.activate(streamer, from: insideUsePosition, toward: insidePosition)
        #expect(runner.enqueuedDoorTransitions == [FormID(0x10), FormID(0x20)])
        let outsideScene = Self.interactiveScene(
            location: .exterior(Self.coordinate(0, 0)), door: outside
        )
        runner.completeDoorTransition(from: FormID(0x20), with: .success(DoorTransition(
            sourceDoor: FormID(0x20),
            destinationDoor: FormID(0x10),
            destinationPlacement: PlacedReference.Placement(
                position: Self.center, rotation: .zero
            ),
            scene: outsideScene
        )))
        streamer.update(cameraPosition: insidePosition)
        #expect(!streamer.isInterior)
        #expect(cameras.last.flatMap(\.self)?.eye == Self.center)
    }

    private static func interactiveScene(
        location: CellSceneLocation,
        door: PlacedDoor,
        sounds: ModelBase.Sounds? = nil
    ) -> CellScene {
        let reference = door.reference
        return cellScene(
            location: location,
            doors: [door],
            interactions: [
                reference: interaction(
                    reference: reference.rawValue,
                    position: door.position,
                    sounds: sounds
                )
            ],
            staticCollision: collision(
                reference: reference.rawValue,
                position: door.position
            )
        )
    }

    private static func activate(
        _ streamer: CellStreamer,
        from origin: SIMD3<Float>,
        toward target: SIMD3<Float>
    ) {
        streamer.update(
            cameraPosition: origin,
            interactionRay: interactionRay(from: origin, to: target),
            activate: true
        )
    }
}
