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
        let moved = runtime.worldDecals { _ in SkinDecalFrames(feet: Self.at(100, 0), bones: [:]) }
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
        #expect(runtime.worldDecals { _ in SkinDecalFrames(feet: nil, bones: [:]) }.isEmpty)
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

    @Test func aDecalRidesTheNearestBodyBone() throws {
        let look = try #require(Self.look)
        var runtime = SkinDecalRuntime()
        let bones = [
            "NPC R Forearm [RLar]": Self.at(20, 0),
            "NPC Head [Head]": Self.at(0, 0),
            "WEAPON": Self.at(21, 0)
        ]
        try #require(runtime.place(
            look, on: Self.actor, at: SIMD3(25, 0, 0), ownerTransform: Self.at(0, 0), bones: bones
        ) != nil)
        let id = try #require(runtime.decals.decals.first?.id)
        #expect(runtime.bones[id] == "NPC R Forearm [RLar]")
        let raised = SkinDecalFrames(
            feet: Self.at(0, 0), bones: ["NPC R Forearm [RLar]": Self.at(20, 50)]
        )
        let decal = try #require(runtime.worldDecals { _ in raised }.first)
        #expect(abs(decal.center.y - 50) < 1e-3)
        #expect(decal.center.x > 20)
    }

    @Test func aDecalWhoseBoneIsGoneIsLeftOut() throws {
        let look = try #require(Self.look)
        var runtime = SkinDecalRuntime()
        runtime.place(
            look, on: Self.actor, at: SIMD3(25, 0, 0), ownerTransform: Self.at(0, 0),
            bones: ["NPC Spine [Spn0]": Self.at(20, 0)]
        )
        #expect(runtime.worldDecals { _ in
            SkinDecalFrames(feet: Self.at(0, 0), bones: [:])
        }.isEmpty)
    }
}
