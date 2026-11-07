// Current lists, water boxes, and the current's push on an actor.

@testable import OpenSkyFormatsESM
import OpenSkyFormatsMesh
@testable import OpenSkyPhysics
import simd
import Testing

struct WaterCurrentTests {
    private let havok = NIFCollisionModel.havokToEngineScale

    private func vector(_ value: SIMD3<Float>, _ last: Float = 0) -> CellExtras.WaterVelocity {
        CellExtras.WaterVelocity(velocity: value, unknown: last)
    }

    private func kind(_ code: Int32) -> Float {
        Float(bitPattern: UInt32(bitPattern: code))
    }

    @Test func aRiverListIsOneCurrentOverTheWholeBoxInGameUnits() {
        let currents = WaterCurrentList.decode([
            vector(SIMD3(2.54, 1.35, 0)), vector(.zero), vector(.zero, kind(0))
        ])
        #expect(currents.count == 1)
        #expect(currents.first?.shape == .everywhere)
        #expect(simd_distance(currents[0].linear, SIMD3(2.54, 1.35, 0) * havok) < 0.001)
    }

    @Test func aPlaneCurrentReadsFourVectorsAndAnUnknownKindStops() {
        let currents = WaterCurrentList.decode([
            vector(SIMD3(1, 0, 0)), vector(.zero, 0.5), vector(SIMD3(0, 0, 0), kind(3)),
            vector(SIMD3(0, 0, 1), 2),
            vector(.zero), vector(.zero), vector(.zero, kind(2))
        ])
        #expect(currents.count == 1)
        #expect(currents.first?.edgeStrength == 0.5)
        #expect(currents.first?.shape == .plane(
            point: .zero,
            normal: SIMD3(0, 0, 1),
            radius: 2 * havok
        ))
    }

    @Test func aShapedCurrentFadesFromItsCentreToItsEdgeStrength() {
        let current = WaterCurrent(
            shape: .cylinder(centre: .zero, radius: 100), linear: SIMD3(10, 0, 0),
            edgeStrength: 0.2
        )
        #expect(current.strength(at: .zero) == 1)
        #expect(abs((current.strength(at: SIMD3(50, 0, 0)) ?? 0) - 0.6) < 0.0001)
        #expect(current.strength(at: SIMD3(150, 0, 0)) == nil)
    }

    @Test func kindZeroCurrentsAddAndAShapedOneBlendsOverThem() {
        let currents = [
            WaterCurrent(shape: .everywhere, linear: SIMD3(10, 0, 0)),
            WaterCurrent(shape: .everywhere, linear: SIMD3(0, 10, 0)),
            WaterCurrent(shape: .cylinder(centre: .zero, radius: 100), linear: SIMD3(0, 0, 30))
        ]
        #expect(currents.velocity(at: SIMD3(200, 0, 0)) == SIMD3(10, 10, 0))
        let blended = currents.velocity(at: SIMD3(50, 0, 0))
        #expect(simd_distance(blended, SIMD3(5, 5, 15)) < 0.0001)
    }

    @Test func aPlaneCountsOnlyBehindItsNormal() {
        let plane = WaterCurrent(
            shape: .plane(point: .zero, normal: SIMD3(0, 0, 1), radius: 100), linear: SIMD3(1, 0, 0)
        )
        #expect(plane.strength(at: SIMD3(0, 0, -10)) != nil)
        #expect(plane.strength(at: SIMD3(0, 0, 10)) == nil)
    }

    @Test func aRadialCurrentTurnsAroundItsCentre() {
        let swirl = WaterCurrent(
            shape: .cylinder(centre: .zero, radius: 100), linear: SIMD3(10, 0, 0), isRadial: true
        )
        let velocity = swirl.velocity(at: SIMD3(50, 0, 0))
        #expect(simd_distance(velocity, SIMD3(0, 10, 0)) < 0.0001)
    }

    @Test func aMissingPlaneSpeedReadsSixAlongTheShapesYAxis() {
        let turned = float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
        let plane = WaterCurrentList.plane(
            shape: turned,
            boundRadius: 50,
            linear: nil,
            angular: nil
        )
        #expect(simd_distance(plane.linear, SIMD3(-6, 0, 0) * havok) < 0.01)
        guard case let .plane(point, _, radius) = plane.shape else {
            Issue.record("not a plane")
            return
        }
        #expect(abs(point.z - 0.5 * havok) < 0.001)
        #expect(radius == 50)
    }

    @Test func theHighestSurfaceWinsAndAPlaneBoxBlendsItsCurrentIn() throws {
        let low = try #require(WaterVolume(
            transform: matrix_identity_float4x4, halfExtents: SIMD3(100, 100, 50), surface: 50,
            currents: [WaterCurrent(shape: .everywhere, linear: SIMD3(10, 0, 0))]
        ))
        let high = try #require(WaterVolume(
            transform: matrix_identity_float4x4, halfExtents: SIMD3(100, 100, 50), surface: 60,
            currents: [WaterCurrent(shape: .everywhere, linear: SIMD3(20, 0, 0))],
            isDangerous: true
        ))
        let planes = try #require(WaterVolume(
            transform: matrix_identity_float4x4, halfExtents: SIMD3(100, 100, 100), surface: nil,
            currents: [WaterCurrent(
                shape: .plane(point: SIMD3(0, 0, 200), normal: SIMD3(0, 0, 1), radius: 1000),
                linear: SIMD3(0, 40, 0), edgeStrength: 1
            )]
        ))
        let reading = try #require(WaterVolumeSet(volumes: [low, high, planes]).candidates(
            at: SIMD3(0, 0, 0)
        ).sample(at: SIMD3(0, 0, 0)))
        #expect(reading.surface == 60)
        #expect(reading.isDangerous)
        #expect(reading.current == SIMD3(0, 40, 0))
        let above = WaterVolumeSet(volumes: [low]).candidates(at: SIMD3(0, 0, 500))
            .sample(at: SIMD3(0, 0, 500))
        #expect(above?.surface == 50)
        #expect(above?.current == .zero)
    }

    @Test func aStrongCurrentPushesInFullAndAWeakOneOnlyASwimmer() {
        let strong = SIMD3<Float>(4 * havok, 0, 0)
        let wading = WaterPushActor(
            ownVelocity: .zero, verticalVelocity: 0, isSwimming: false, maximumSpeed: 300
        )
        #expect(WaterCurrentPush.velocity(current: strong, actor: wading) == strong)
        let weak = SIMD3<Float>(2 * havok, 0, 0)
        #expect(WaterCurrentPush.velocity(current: weak, actor: wading) == .zero)
        var swimmer = wading
        swimmer.isSwimming = true
        #expect(WaterCurrentPush.velocity(current: weak, actor: swimmer) == weak)
        swimmer.ownVelocity = SIMD2(250, 0)
        let capped = WaterCurrentPush.velocity(current: weak, actor: swimmer)
        #expect(abs(capped.x - 50) < 0.01)
        var fish = swimmer
        fish.race = WaterPushRace(strongCurrent: 3.75, isSwimOnly: true)
        #expect(WaterCurrentPush.velocity(current: strong, actor: fish) == .zero)
    }
}
