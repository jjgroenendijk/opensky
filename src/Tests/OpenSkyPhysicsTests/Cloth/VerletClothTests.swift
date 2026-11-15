// The cape cloth over a synthetic strip: three columns and six rows in the x-z plane, 10
// units apart. The top four rows are the 12 pins. See docs/engine/cape-cloth.md.

import OpenSkyPhysics
import simd
import Testing

struct VerletClothTests {
    private static let columns = 3
    private static let rows = 6

    private static var rest: [SIMD3<Float>] {
        (0 ..< rows).flatMap { row in
            (0 ..< columns).map { column in SIMD3(Float(column) * 10, 0, Float(row) * 10) }
        }
    }

    private static var triangles: [UInt16] {
        (0 ..< rows - 1).flatMap { row in
            (0 ..< columns - 1).flatMap { column -> [UInt16] in
                let corner = UInt16(row * columns + column)
                let above = corner + UInt16(columns)
                return [corner, corner + 1, above, corner + 1, above + 1, above]
            }
        }
    }

    private static func cloth(at shape: float4x4 = matrix_identity_float4x4) throws -> VerletCloth {
        try #require(VerletCloth(rest: rest, triangles: triangles, shapeToWorld: shape))
    }

    @Test func theTwelveHighestVerticesArePinned() throws {
        let pins = try Self.cloth().pins
        #expect(pins.count == VerletCloth.pinCount)
        #expect(pins.allSatisfy { Self.rest[$0].z >= 20 })
    }

    @Test func aFreeVertexFallsAndTheEdgesHoldIt() throws {
        var cloth = try Self.cloth()
        let corner = 0
        for _ in 0 ..< 30 {
            cloth.step(seconds: 1 / 60, shapeToWorld: matrix_identity_float4x4, capsules: [])
        }
        let fallen = cloth.positions[corner]
        let above = cloth.positions[Self.columns]
        #expect(abs(simd_distance(fallen, above) - 10) < 0.5)
        #expect(cloth.positions[18 - 1] == Self.rest[18 - 1])
    }

    @Test func aPausedFrameMovesNothing() throws {
        var cloth = try Self.cloth()
        let before = cloth.positions
        cloth.step(seconds: 0, shapeToWorld: matrix_identity_float4x4, capsules: [])
        #expect(cloth.positions == before)
    }

    @Test func thePinsFollowTheShape() throws {
        var cloth = try Self.cloth()
        let moved = float4x4(
            SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(100, 0, 0, 1)
        )
        cloth.step(seconds: 1 / 60, shapeToWorld: moved, capsules: [])
        let top = Self.rest.count - 1
        #expect(cloth.positions[top] == Self.rest[top] + SIMD3(100, 0, 0))
        #expect(cloth.localPositions(shapeToWorld: moved)[top] == Self.rest[top])
    }

    @Test func aCapsulePushesTheClothOut() throws {
        var cloth = try Self.cloth()
        let capsule = ClothCapsule(
            start: SIMD3(-50, 0, -2), end: SIMD3(50, 0, -2), radius: 4
        )
        cloth.step(seconds: 1 / 60, shapeToWorld: matrix_identity_float4x4, capsules: [capsule])
        for index in 0 ..< Self.columns {
            let point = cloth.positions[index]
            #expect(simd_length(SIMD2(point.y, point.z + 2)) >= 4 - 0.001)
        }
    }
}
