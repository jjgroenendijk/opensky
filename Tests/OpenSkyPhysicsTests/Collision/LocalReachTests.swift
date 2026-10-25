// The local-space box that lets a triangle soup skip triangles a sphere cannot touch.

@testable import OpenSkyPhysics
import simd
import Testing

struct LocalReachTests {
    /// Turned a quarter about z, stretched to 3, 1, and 0.5, and moved.
    private static let placement: float4x4 = {
        var matrix = float4x4(simd_quatf(angle: .pi / 2, axis: SIMD3(0, 0, 1)))
            * float4x4(diagonal: SIMD4(3, 1, 0.5, 1))
        matrix.columns.3 = SIMD4(100, -50, 20, 1)
        return matrix
    }()

    @Test func aTriangleUnderTheSphereIsKept() throws {
        let local = SIMD3<Float>(4, -2, 6)
        let world = (Self.placement * SIMD4(local, 1))
        let reach = try #require(
            LocalReach(point: SIMD3(world.x, world.y, world.z), slack: 2, transform: Self.placement)
        )
        #expect(reach.mayTouch(local, local + SIMD3(1, 0, 0), local + SIMD3(0, 1, 0)))
    }

    @Test func everyTriangleWithinTheSlackInWorldSpaceIsKept() throws {
        let center = SIMD3<Float>(0, 0, 0)
        let world = Self.placement * SIMD4(center, 1)
        let reach = try #require(
            LocalReach(point: SIMD3(world.x, world.y, world.z), slack: 2, transform: Self.placement)
        )
        // 1.9 world units away along the most squashed local axis, z (scale 0.5).
        let near = SIMD3<Float>(0, 0, 3.8)
        #expect(reach.mayTouch(near, near, near))
    }

    @Test func aFarTriangleIsSkipped() throws {
        let world = Self.placement * SIMD4(0, 0, 0, 1)
        let reach = try #require(
            LocalReach(point: SIMD3(world.x, world.y, world.z), slack: 2, transform: Self.placement)
        )
        let far = SIMD3<Float>(500, 500, 500)
        #expect(!reach.mayTouch(far, far + SIMD3(1, 0, 0), far + SIMD3(0, 1, 0)))
    }

    @Test func aFlatPlacementTestsEveryTriangle() {
        let flat = float4x4(diagonal: SIMD4(1, 1, 0, 1))
        #expect(LocalReach(point: .zero, slack: 1, transform: flat) == nil)
    }
}
