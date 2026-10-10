// An impact through the effects coordinator: its model as a timed effect, its
// decal on the ground under a struck actor, and the switches that turn each off.

import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import simd
import Testing

@MainActor
private final class FeetWorld: EffectsWorld {
    func effectTransform(of _: ReferenceKey) -> float4x4? {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(10, 20, -5, 1)
        return transform
    }

    func membraneTarget(of _: ReferenceKey) -> MembraneTarget? {
        nil
    }

    func detonateEffectExplosion(_: ReferenceKey, at _: SIMD3<Float>) {}
}

@MainActor
struct EffectsCoordinatorImpactTests {
    static let decal = ImpactDecal(
        diffusePath: "Effects\\Blood01.dds", decal: DecalData(width: 10 ... 10, height: 6 ... 6)
    )

    static func impact(model: String?) throws -> Impact {
        var fields = Data()
        if let model {
            fields += ESMFixture.field("MODL", ESMFixture.zstring(model))
        }
        let bytes = ESMFixture.record("IPCT", formID: 0x300, data: fields)
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else { throw ESMError.malformed("none") }
        return try Impact(record: record)
    }

    @Test func anActorHitShowsTheModelAndMarksTheGroundUnderIt() throws {
        let world = FeetWorld()
        let effects = EffectsCoordinator()
        effects.world = world
        try effects.showImpact(
            Self.impact(model: "Effects\\ImpactEffects\\Blood.nif"),
            decal: Self.decal, at: SIMD3(12, 22, 60), on: .actor(.player)
        )

        #expect(effects.visualEffects.instances.map(\.cause) == [.impact])
        let decal = try #require(effects.decals.decals.first)
        #expect(decal.look.texture == "textures/effects/blood01.dds")
        #expect(abs(decal.center.z - (-5 + DecalRuntime.surfaceOffset)) < 1e-4)
        #expect(SIMD2(decal.center.x, decal.center.y) == SIMD2(12, 22))
        #expect(effects.impactCount == 1)
        #expect(effects.lastImpact?.decal == Self.decal)
    }

    @Test func theSwitchesTurnModelsAndDecalsOff() throws {
        let effects = EffectsCoordinator()
        effects.impactModelsEnabled = false
        effects.decalsEnabled = false
        try effects.showImpact(
            Self.impact(model: "Effects\\Dust.nif"), decal: Self.decal, at: .zero, on: .ground
        )
        #expect(effects.visualEffects.instances.isEmpty)
        #expect(effects.decals.decals.isEmpty)
    }

    @Test func repeatingNeedsAnImpactFirst() throws {
        let effects = EffectsCoordinator()
        let world = FeetWorld()
        effects.world = world
        #expect(!effects.repeatLastImpact())
        try effects.showImpact(Self.impact(model: nil), decal: Self.decal, at: .zero, on: .ground)
        #expect(effects.repeatLastImpact())
        #expect(effects.decals.decals.count == 2)
        withExtendedLifetime(world) {}
    }
}
