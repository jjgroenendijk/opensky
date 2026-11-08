// The effects shell without a renderer: the player settings it follows, the blood
// settings it reads, the low-health cues, effect anchors, and spell hits over
// records that name nothing.

import Foundation
@testable import OpenSkyEffects
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
@testable import OpenSkyMagicInterface
@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import OpenSkyWorldInterface
import simd
import Testing

@MainActor
private final class PointWorld: EffectsWorld {
    var detonations: [(ReferenceKey, SIMD3<Float>)] = []

    var effectCamera: VisualEffectRuntime.CameraPose? {
        nil
    }

    func effectTransform(of _: ReferenceKey) -> float4x4? {
        EffectsCoordinator.translation(SIMD3(1, 2, 3))
    }

    func membraneTarget(of _: ReferenceKey) -> MembraneTarget? {
        nil
    }

    func detonateEffectExplosion(_ explosion: ReferenceKey, at position: SIMD3<Float>) {
        detonations.append((explosion, position))
    }
}

@MainActor
struct EffectsCoordinatorShellTests {
    private static let target = ReferenceKey.plugin(name: "Skyrim.esm", objectID: 0x14)

    private static func hit(links: [SpellHitEffectLinks]) -> SpellHitEvent {
        let payload = SpellPayload(
            spell: .plugin(name: "Skyrim.esm", objectID: 0x12FCD), sourcePlugin: "Skyrim.esm",
            caster: .player, entries: [], isHostile: true, ignoresResistance: false,
            projectile: nil, name: "Flames"
        )
        return SpellHitEvent(
            hit: SpellHit(payload: payload, targets: [SpellHitTarget(key: target)]), links: links
        )
    }

    @Test func playerSettingsTurnEachEffectOnOrOff() {
        let store = PlayerSettingsStore(persistence: nil)
        let effects = EffectsCoordinator()
        store.set(.impactEffects, to: 0)
        store.set(.decals, to: 1)
        store.set(.skinDecals, to: 0)
        store.set(.decalLimit, to: 40)
        store.set(.decalsPerFrame, to: .infinity)
        effects.applyGraphicsSettings(store)
        #expect(!effects.impactModelsEnabled)
        #expect(effects.decalsEnabled)
        #expect(!effects.skinDecalsEnabled)
        #expect(effects.decalLimit == 40)
        #expect(effects.decals.perFrameLimit == 0)
    }

    @Test func bloodSettingsReadTheGameSettingsAndKeepTheRest() throws {
        let file = try GameSettingFixture.plugin(settings: [
            "fBloodSplatterDuration": .float(12), "iBloodSplatterMaxCount": .integer(9)
        ])
        let settings = BloodEffectSettings.resolve(
            store: GameSettingStore(plugins: [("Blood.esp", file)])
        )
        #expect(settings.duration == 12)
        #expect(settings.maxCount == 9)
        #expect(settings.flareSize == BloodEffectSettings.vanilla.flareSize)
        #expect(BloodEffectSettings.resolve(store: GameSettingStore(plugins: [])) == .vanilla)
    }

    /// A reset forgets the last health share, so the same share starts the heartbeat again.
    @Test func resetHealthCuesStartsTheHeartbeatAgain() {
        let effects = EffectsCoordinator()
        var imageSpace = ImageSpaceState()
        func step() -> HeartbeatChange? {
            effects.stepHealthCues(
                share: 0.15, seconds: 0.1, heartbeatPlaying: true, imageSpace: &imageSpace
            )
        }
        #expect(step() == .start(.slow))
        #expect(step() == nil)
        effects.resetHealthCues()
        #expect(step() == .start(.slow))
    }

    @Test func healthCuesWaitWhileTheWorldIsPaused() {
        let effects = EffectsCoordinator()
        var imageSpace = ImageSpaceState()
        let paused = effects.stepHealthCues(
            share: 0.1, seconds: 0, heartbeatPlaying: false, imageSpace: &imageSpace
        )
        #expect(paused == nil)
        _ = effects.stepHealthCues(
            share: 0.1, seconds: 0.5, heartbeatPlaying: false, imageSpace: &imageSpace
        )
        #expect(effects.heartbeatSound(.slow) == nil)
        #expect(effects.heartbeatSound(.fast) == nil)
    }

    @Test func anchorsPlaceTheirModel() {
        let world = PointWorld()
        let point = EffectsCoordinator.locate(.point(SIMD3(4, 5, 6)), world: world)
        #expect(point?.columns.3 == SIMD4(4, 5, 6, 1))
        let actor = EffectsCoordinator.locate(.actor(.player), world: world)
        #expect(actor?.columns.3 == SIMD4(1, 2, 3, 1))
        #expect(EffectsCoordinator.locate(.actor(.player), world: nil) == nil)
        let surface = EffectsCoordinator.locate(.surface(.zero, normal: SIMD3(0, 0, 1)), world: nil)
        #expect(surface?.columns.3 == SIMD4(0, 0, 0, 1))
        let facing = EffectsCoordinator.locate(.facing(.one, forward: SIMD3(0, 1, 0)), world: nil)
        #expect(facing?.columns.3 == SIMD4(1, 1, 1, 1))
    }

    @Test func recordsThatNameNothingDrawNothing() {
        let effects = EffectsCoordinator()
        var imageSpace = ImageSpaceState()
        let key = ReferenceKey.plugin(name: "Skyrim.esm", objectID: 0x99)
        #expect(effects.detach(key, from: .actor(.player)) == 0)
        #expect(!effects.showCastingArt(
            FormID(0x99),
            fromPlugin: "Skyrim.esm",
            on: .player,
            shown: true
        ))
        #expect(!effects.showCastingArt(
            FormID(0x99),
            fromPlugin: "Skyrim.esm",
            on: .player,
            shown: false
        ))
        #expect(!effects.startModifier(key, strength: 1, on: &imageSpace))
        effects.stopModifier(key, on: &imageSpace)
        effects.attachLasting(
            [SpellHitEffectLinks(plugin: "Skyrim.esm", hitShader: FormID(0x99))],
            to: .player
        )
        #expect(effects.visualEffects.models(camera: nil) { _ in nil }.isEmpty)
    }

    @Test func aSpellHitCountsItsTargetsAndEffects() {
        let world = PointWorld()
        let effects = EffectsCoordinator(world: world)
        var imageSpace = ImageSpaceState()
        let links = [
            SpellHitEffectLinks(
                plugin: "Skyrim.esm", imageSpaceModifier: FormID(0x50), hitShader: FormID(0x51),
                explosion: FormID(0x52), area: 10
            )
        ]
        effects.handleSpellHit(Self.hit(links: links), imageSpace: &imageSpace)
        #expect(effects.spellHitCount == 1)
        #expect(effects
            .lastSpellHit == "Flames: 1 target(s), 0 effect(s), 0 image-space modifier(s)")
        effects.detonateAreaExplosions(of: Self.hit(links: links))
        #expect(world.detonations.isEmpty)
    }
}
