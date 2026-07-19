// Deterministic clean engine values for M4.5 route. No game payload.

@testable import opensky
import simd
import Testing

struct WalkPathRouteTests {
    @Test func exteriorRouteStartsInM2CellAndEndsAtFarmDoor() throws {
        let first = try #require(WalkPathRoute.exteriorWaypoints.first)
        let last = try #require(WalkPathRoute.exteriorWaypoints.last)
        #expect(CellGridManager.cellCoordinate(for: SIMD3(first.x, first.y, 0)) == .init(
            x: 6, y: -2
        ))
        #expect(CellGridManager.cellCoordinate(for: SIMD3(last.x, last.y, 0)) == .init(
            x: 7, y: -3
        ))
        #expect(simd_distance(last, WalkPathRoute.exteriorReturn) < 0.01)
        #expect(WalkPathRoute.farmDoor == FormID(0x0001_633D))
        #expect(WalkPathRoute.interiorDoor == FormID(0x0001_63A8))
        #expect(WalkPathRoute.farmInterior == FormID(0x0001_6204))
    }

    @Test func yawAndInteriorCrossingAreDeterministic() {
        let start = SIMD2<Float>(10, 20)
        #expect(abs(WalkPathRoute.yaw(from: start, to: SIMD2(10, 30)) - .pi / 2) < 0.001)
        let target = WalkPathRoute.interiorTarget(from: start, yaw: 0)
        #expect(target == SIMD2(10 + WalkPathRoute.interiorCrossingDistance, 20))
    }
}
