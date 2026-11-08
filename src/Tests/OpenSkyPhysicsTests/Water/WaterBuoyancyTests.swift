// A loose body in water: how deep it sits, how much it lifts, and that a current
// carries it downstream.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPhysics
import simd
import Testing

struct WaterBuoyancyTests {
    @Test func theFillCountsFromAQuarterUpTheBoxOverSixTenthsOfIt() {
        let box = ModelBounds(min: SIMD3(0, 0, 0), max: SIMD3(10, 10, 100))
        #expect(WaterBuoyancy.fill(bounds: box, surface: 25) == 0)
        #expect(abs(WaterBuoyancy.fill(bounds: box, surface: 85) - 1) < 0.0001)
    }

    @Test func liftRampsInBetweenHalfAndThreeQuartersFull() {
        #expect(WaterBuoyancy.lift(fill: 0.4, buoyancy: 2) == 0)
        #expect(abs(WaterBuoyancy.lift(fill: 0.625, buoyancy: 2) - 1) < 0.0001)
        #expect(WaterBuoyancy.lift(fill: 0.9, buoyancy: 2) == 2)
    }

    private func river(current: SIMD3<Float>) -> DynamicWaterWorld {
        let box = WaterVolume(
            transform: matrix_identity_float4x4, halfExtents: SIMD3(100_000, 100_000, 500),
            surface: 0, currents: [WaterCurrent(shape: .everywhere, linear: current)]
        )
        let volumes = WaterVolumeSet(volumes: box.map { [$0] } ?? [])
        return DynamicWaterWorld(
            sample: { volumes.candidates(at: $0).sample(at: $0) }, player: nil
        )
    }

    private func floatingCube(at centre: SIMD3<Float>, buoyancy: Float) -> DynamicBody {
        let cube = DynamicBodyScene.cube(key: .generated(1), center: centre)
        var definition = cube.definition
        definition.buoyancy = buoyancy
        return DynamicBody(
            key: cube.key, reference: cube.reference, cell: .interior(FormID(0x10)),
            definition: definition, originPosition: centre, orientation: cube.orientation
        )
    }

    @Test func aBuoyantBodyComesUpAndDriftsDownstream() {
        let world = DynamicStepWorld(water: river(current: SIMD3(200, 0, 0)))
        var bodies = [floatingCube(at: SIMD3(0, 0, -200), buoyancy: 2)]
        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 600)
        #expect(bodies[0].position.z > -40)
        #expect(bodies[0].position.x > 500)
        // Water slows a body above 2 Havok units a second, so it drifts near that speed.
        #expect(bodies[0].linearVelocity.x > WaterBuoyancy.horizontalDampingFloor * 0.8)
    }

    @Test func aBodyWithNoBuoyancyHangsWhereItIs() {
        let world = DynamicStepWorld(water: river(current: .zero))
        var bodies = [floatingCube(at: SIMD3(0, 0, -200), buoyancy: 0)]
        DynamicBodyScene.run(bodies: &bodies, world: world, steps: 120)
        #expect(abs(bodies[0].position.z + 200) < 1)
    }
}
