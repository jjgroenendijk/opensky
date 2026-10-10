// The decal runtime: a placed decal lies flat on its surface inside the DODT
// size range, the subtexture grid, the limit dropping the oldest, and off.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
import simd
import Testing

struct DecalRuntimeTests {
    static let blood = DecalLook(
        texture: "textures/decals/blood01.dds",
        decal: DecalData(width: 12 ... 24, height: 8 ... 20, color: SIMD3(255, 128, 0))
    )

    @Test func aDecalLiesOnItsSurfaceInsideTheSizeRange() throws {
        let look = try #require(Self.blood)
        var runtime = DecalRuntime()
        let wall = SIMD3<Float>(1, 0, 0)
        try #require(runtime.place(look, at: SIMD3(100, 0, 50), normal: wall * 3) != nil)

        let decal = try #require(runtime.decals.first)
        #expect(simd_distance(decal.normal, wall) < 1e-4)
        #expect(abs(simd_dot(decal.axisU, wall)) < 1e-4)
        #expect(abs(simd_dot(decal.axisV, wall)) < 1e-4)
        #expect((12 ... 24).contains(simd_length(decal.axisU) * 2 + 1e-4))
        #expect((8 ... 20).contains(simd_length(decal.axisV) * 2 + 1e-4))
        #expect(simd_distance(decal.center, SIMD3(100.5, 0, 50)) < 1e-4)
        #expect(decal.look.color == SIMD3(1, 128.0 / 255, 0))
    }

    @Test func aGridTexturePicksOneCellAndASingleTextureUsesAll() throws {
        let grid = try #require(Self.blood)
        let single = try #require(DecalLook(
            texture: "textures/decals/scorch.dds",
            decal: DecalData(width: 10 ... 10, height: 10 ... 10, flags: .noSubtextures)
        ))
        var runtime = DecalRuntime()
        runtime.place(grid, at: .zero, normal: SIMD3(0, 0, 1))
        runtime.place(single, at: .zero, normal: SIMD3(0, 0, 1))

        let cell = runtime.decals[0].uvRect
        #expect(cell.z == 0.5 && cell.w == 0.5)
        #expect([0, 0.5].contains(cell.x) && [0, 0.5].contains(cell.y))
        #expect(runtime.decals[1].uvRect == SIMD4(0, 0, 1, 1))
    }

    @Test func theLimitDropsTheOldest() throws {
        let look = try #require(Self.blood)
        var runtime = DecalRuntime()
        runtime.limit = 2
        for index in 0 ..< 3 {
            runtime.place(look, at: SIMD3(Float(index), 0, 0), normal: SIMD3(0, 0, 1))
        }
        #expect(runtime.decals.map(\.id) == [2, 3])
        #expect(runtime.placedTotal == 3)

        runtime.limit = 1
        #expect(runtime.decals.map(\.id) == [3])
    }

    @Test func offOrADegenerateNormalPlacesNothing() throws {
        let look = try #require(Self.blood)
        var runtime = DecalRuntime()
        #expect(runtime.place(look, at: .zero, normal: .zero) == nil)
        runtime.enabled = false
        #expect(runtime.place(look, at: .zero, normal: SIMD3(0, 0, 1)) == nil)
        #expect(runtime.decals.isEmpty)
    }

    @Test func aDecalWithNoSizeHasNoLook() {
        #expect(DecalLook(
            texture: "textures/decals/x.dds", decal: DecalData(width: 0 ... 0, height: 4 ... 4)
        ) == nil)
    }

    @Test func theBasisIsRightHandedAroundTheNormal() {
        let normals: [SIMD3<Float>] = [
            SIMD3(0, 0, 1), SIMD3(0, 0, -1), simd_normalize(SIMD3<Float>(1, 2, 0.5))
        ]
        for normal in normals {
            let (tangent, bitangent) = DecalRuntime.basis(around: normal, angle: 1.3)
            #expect(simd_distance(simd_cross(tangent, bitangent), normal) < 1e-4)
        }
    }
}
