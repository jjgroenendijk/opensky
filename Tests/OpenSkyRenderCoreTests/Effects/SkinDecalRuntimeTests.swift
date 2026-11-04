// Skin decals: kept in the actor's frame, so they follow it, sized for a body, and
// limited per frame and in total.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyRenderCore
import simd
import Testing

struct SkinDecalRuntimeTests {
    static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x14)
    static let look = DecalLook(
        texture: "textures/decals/blood01.dds",
        decal: DecalData(width: 40 ... 60, height: 40 ... 60, flags: .noSubtextures)
    )

    static func at(_ x: Float, _ y: Float) -> float4x4 {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(x, y, 0, 1)
        return transform
    }

    @Test func aDecalFollowsItsActor() throws {
        let look = try #require(Self.look)
        var runtime = SkinDecalRuntime()
        try #require(runtime.place(
            look, on: Self.actor, at: SIMD3(10, 0, 60), ownerTransform: Self.at(0, 0)
        ) != nil)
        let moved = runtime.worldDecals { _ in Self.at(100, 0) }
        let decal = try #require(moved.first)
        #expect(abs(decal.center.x - 110.5) < 1e-3)
        #expect(abs(decal.center.z - 60) < 1e-3)
        #expect(abs(decal.normal.x - 1) < 1e-3)
    }

    @Test func aDecalOnABodyIsSmall() throws {
        let look = try #require(Self.look)
        var runtime = SkinDecalRuntime()
        runtime.place(look, on: Self.actor, at: SIMD3(0, 10, 60), ownerTransform: Self.at(0, 0))
        let decal = try #require(runtime.decals.decals.first)
        #expect(simd_length(decal.axisU) * 2 <= SkinDecalRuntime.maximumSize + 1e-3)
    }

    @Test func aDecalWithoutItsActorIsLeftOut() throws {
        let look = try #require(Self.look)
        var runtime = SkinDecalRuntime()
        runtime.place(look, on: Self.actor, at: SIMD3(0, 10, 60), ownerTransform: Self.at(0, 0))
        #expect(runtime.worldDecals { _ in nil }.isEmpty)
    }

    @Test func theFrameLimitDropsExtraDecals() throws {
        let look = try #require(Self.look)
        var runtime = SkinDecalRuntime()
        runtime.decals.perFrameLimit = 1
        runtime.place(look, on: Self.actor, at: SIMD3(0, 10, 60), ownerTransform: Self.at(0, 0))
        let second = runtime.place(
            look, on: Self.actor, at: SIMD3(0, -10, 60), ownerTransform: Self.at(0, 0)
        )
        #expect(second == nil)
        #expect(runtime.decals.decals.count == 1)
    }
}
