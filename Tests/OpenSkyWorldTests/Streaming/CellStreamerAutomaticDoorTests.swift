// An automatic door opens when the player's feet enter its area, once per entry.

@testable import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldInterface
import OpenSkyWorldTesting
import simd
import Testing

private typealias Fixture = CellStreamerFixture

extension CellStreamerTests {
    @Test
    func walkingIntoAnAutomaticDoorStartsItsTransitionOnce() {
        let runner = ManualCellBuildRunner()
        let streamer = Fixture.makeStreamer(runner: runner, radius: 0)
        streamer.update(cameraPosition: Fixture.center)
        let door = Fixture.door(reference: 0x10, destination: 0x20, position: Fixture.center)
        var interaction = Fixture.interaction(reference: 0x10, position: Fixture.center)
        interaction.automaticArea = AutomaticDoorArea(
            worldToLocal: simd_float4x4(translation: -Fixture.center),
            minimum: [-50, -50, 0], maximum: [50, 50, 100]
        )
        runner.complete(Fixture.coordinate(0, 0), with: .success(Fixture.cellScene(
            location: .exterior(Fixture.coordinate(0, 0)),
            doors: [door],
            interactions: [door.reference: interaction]
        )))
        let outside = Fixture.center + SIMD3<Float>(200, 0, 0)
        let walk = { (feet: SIMD3<Float>) in
            streamer.update(
                cameraPosition: feet, playerCapsule: PlayerCapsuleState(feetPosition: feet)
            )
        }
        walk(outside)
        walk(outside)
        #expect(runner.enqueuedDoorTransitions.isEmpty)
        walk(Fixture.center + SIMD3<Float>(10, 0, 0))
        #expect(runner.enqueuedDoorTransitions == [FormID(0x10)])
        walk(Fixture.center)
        #expect(runner.enqueuedDoorTransitions == [FormID(0x10)])
    }
}

extension simd_float4x4 {
    fileprivate init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}
