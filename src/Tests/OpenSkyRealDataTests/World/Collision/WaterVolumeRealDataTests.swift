// A vanilla river cell over the user's install: its placed river water becomes a
// water box with the water type's current, and a loose body dropped in it drifts
// downstream (docs/engine/water-physics.md).

import Foundation
@testable import OpenSkyCells
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyPhysics
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.gpu))
struct WaterVolumeRealDataTests {
    /// Tamriel (19, -8) holds `Water1024RiverFlowNE` references.
    private static let riverCell = (x: Int32(19), y: Int32(-8))

    @Test(.enabled(if: RealDataEnvironment.canRender))
    func aRiverCellCarriesItsCurrentAndALooseBodyDrifts() throws {
        let builder = try RealDataInstall.load().sceneBuilder(readsLooseFiles: true)
        let scene = try builder.buildScene(
            worldspaceEditorID: "Tamriel", gridX: Self.riverCell.x, gridY: Self.riverCell.y
        )
        let rivers = scene.waterVolumes.volumes.filter { $0.surface != nil && !$0.currents.isEmpty }
        let river = try #require(rivers.first { simd_length($0.currents[0].linear) > 1 })
        let flow = river.currents[0].linear
        // `RiverWaterFlowNE` flows north-east.
        #expect(flow.x > 0 && flow.y > 0)
        let surface = try #require(river.surface)
        let centre = river.transform.columns.3
        let start = SIMD3(centre.x, centre.y, surface - 40)
        let reading = try #require(scene.waterVolumes.candidates(at: start).sample(at: start))
        #expect(reading.surface >= surface)

        let volumes = scene.waterVolumes
        let world = DynamicStepWorld(water: DynamicWaterWorld(
            sample: { volumes.candidates(at: $0).sample(at: $0) }, player: nil
        ))
        let cube = DynamicCollisionVolume.box(halfExtents: SIMD3(repeating: 8))
        var definition = try DynamicBodyDefinition(volumes: #require(cube.map { [$0] }), mass: 2)
        definition.buoyancy = 1.5
        var bodies = [DynamicBody(
            key: .generated(1), reference: FormID(0x100), cell: .interior(FormID(0x10)),
            definition: definition, originPosition: start,
            orientation: simd_quatf(angle: 0, axis: SIMD3(0, 0, 1))
        )]
        for _ in 0 ..< 240 {
            DynamicBodySolver.step(bodies: &bodies, world: world, dt: PhysicsStep.fixedTimeStep)
        }
        let moved = bodies[0].position - start
        #expect(simd_dot(SIMD2(moved.x, moved.y), simd_normalize(SIMD2(flow.x, flow.y))) > 50)
        #expect(bodies[0].position.z > surface - 30)
    }
}
