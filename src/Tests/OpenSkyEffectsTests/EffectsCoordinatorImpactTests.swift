// An impact through the effects coordinator: its model as a timed effect, its decal
// on a struck actor or the ground under it, and the switches that turn each off.

import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyEffects
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsTesting
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
private final class FeetWorld: EffectsWorld {
    var effectCamera: VisualEffectRuntime.CameraPose? {
        nil
    }

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

    @Test func anActorHitMarksTheActorWhileSkinDecalsAreOn() throws {
        let world = FeetWorld()
        let effects = EffectsCoordinator(world: world)
        try effects.showImpact(
            Self.impact(model: nil), decal: Self.decal, at: SIMD3(12, 22, 60), on: .actor(.player)
        )
        #expect(effects.skinDecals.decals.decals.count == 1)
        #expect(Array(effects.skinDecals.owners.values) == [.player])
        #expect(effects.decals.decals.isEmpty)
    }

    @Test func anActorHitShowsTheModelAndMarksTheGroundUnderIt() throws {
        let world = FeetWorld()
        let effects = EffectsCoordinator(world: world)
        effects.skinDecalsEnabled = false
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
        let world = FeetWorld()
        let effects = EffectsCoordinator(world: world)
        #expect(!effects.repeatLastImpact())
        try effects.showImpact(Self.impact(model: nil), decal: Self.decal, at: .zero, on: .ground)
        #expect(effects.repeatLastImpact())
        #expect(effects.decals.decals.count == 2)
        withExtendedLifetime(world) {}
    }

    @Test func aFlashLightFadesAndGoes() {
        let effects = EffectsCoordinator()
        let light = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x900)
        effects.addFlashLight(light, at: SIMD3(1, 2, 3), duration: 2)
        effects.addFlashLight(light, at: .zero, duration: 0)
        #expect(effects.flashLights.count == 1)
        effects.ageFlashLights(0.5)
        #expect(effects.flashLights.first?.strength == 0.75)
        effects.ageFlashLights(2)
        #expect(effects.flashLights.isEmpty)
        for _ in 0 ... EffectsCoordinator.flashLightLimit {
            effects.addFlashLight(light, at: .zero, duration: 1)
        }
        #expect(effects.flashLights.count == EffectsCoordinator.flashLightLimit)
    }
}
