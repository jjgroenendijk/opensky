// Proximity door activation + interior streaming suspension/resume.

@testable import opensky
import simd
import Testing

extension CellStreamerTests {
    @Test
    func proximityDoorEntersInteriorSuspendsGridThenReturns() {
        let runner = ManualCellBuildRunner()
        var cameras: [SceneCamera?] = []
        let streamer = Self.makeStreamer(runner: runner, radius: 0) { _, camera in
            cameras.append(camera)
        }
        streamer.update(cameraPosition: Self.center)
        let outside = Self.door(reference: 0x10, destination: 0x20, position: Self.center)
        runner.complete(Self.coordinate(0, 0), with: .success(Self.cellScene(
            location: .exterior(Self.coordinate(0, 0)), doors: [outside]
        )))
        streamer.update(cameraPosition: Self.center)

        streamer.update(cameraPosition: Self.center + SIMD3(500, 0, 0), activate: true)
        #expect(runner.enqueuedDoorTransitions.isEmpty)
        streamer.update(cameraPosition: Self.center, activate: true)
        #expect(runner.enqueuedDoorTransitions == [FormID(0x10)])

        let insidePosition = SIMD3<Float>(100, 200, 300)
        let inside = Self.door(reference: 0x20, destination: 0x10, position: insidePosition)
        let interior = Self.cellScene(
            location: .interior(FormID(0x138CA)), doors: [inside]
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

        streamer.update(cameraPosition: insidePosition, activate: true)
        #expect(runner.enqueuedDoorTransitions == [FormID(0x10), FormID(0x20)])
        let outsideScene = Self.cellScene(
            location: .exterior(Self.coordinate(0, 0)), doors: [outside]
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
}
