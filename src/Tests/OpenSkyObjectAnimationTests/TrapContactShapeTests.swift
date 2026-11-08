// Trap contact shape: a rigid part's bounds become points in its bone's space, so a
// turning bone moves the blade edge while the pivot stays put.

import OpenSkyFormatsCore
@testable import OpenSkyObjectAnimation
import simd
import Testing

struct TrapContactShapeTests {
    /// A blade hanging 180 units below a pivot bone that sits 256 units up.
    private static let shape: TrapContactShape = {
        let pivot = simd_float4x4(columns: (
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 256, 1]
        ))
        let skin = SkinningPalette(
            boneNames: ["Blade01"],
            rootParentToSkin: matrix_identity_float4x4,
            skinToBoneMatrices: [pivot.inverse],
            bindPoseMatrices: [matrix_identity_float4x4]
        )
        let part = TrapContactPart(
            skinning: skin, bounds: ModelBounds(min: [-30, -5, 76], max: [30, 5, 256])
        )
        return TrapContactShape(boneNames: ["Root", "blade01"], parts: [part])
    }()

    @Test func partPointsFollowTheirBone() throws {
        #expect(Self.shape.points.count == 15)
        #expect(Self.shape.points.allSatisfy { $0.bone == 1 })
        let rest = simd_float4x4(columns: (
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 256, 1]
        ))
        let lowest = try #require(
            Self.shape.positions(posed: [matrix_identity_float4x4, rest]).map(\.z).min()
        )
        #expect(abs(lowest - 76) < 0.001)
        // Turned 90 degrees about y, the blade tip swings out sideways.
        let turned = rest * simd_float4x4(simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
        let swung = Self.shape.positions(posed: [matrix_identity_float4x4, turned])
        let reach = try #require(swung.map { abs($0.x) }.max())
        #expect(abs(reach - 180) < 0.01)
    }

    @Test func withoutPartsTheBoneOriginsStandIn() {
        let bone = simd_float4x4(columns: (
            [1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [4, 5, 6, 1]
        ))
        #expect(TrapContactShape.empty.positions(posed: [bone]) == [[4, 5, 6]])
    }
}
