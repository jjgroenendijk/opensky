// The effect catalog and visual-effect specs over a synthetic plugin, the
// effects coordinator's attach and detach, and the panel readout text.

import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

@MainActor
struct EffectCatalogTests {
    private typealias Fixture = ESMFixture
    static let plugin = "Effects.esm"

    static func records() throws -> EffectRecordStore {
        let file = try Fixture.plugin(records: [
            Fixture.recordBytes("ARTO", formID: 0x800, fields: [
                ("EDID", Fixture.zstring("GlowArt")), ("MODL", Fixture.zstring("fx/glow.nif"))
            ]),
            Fixture.recordBytes("RFCT", formID: 0x801, fields: [
                ("EDID", Fixture.zstring("GlowEffect")), ("DATA", Fixture.u32(0x800, 0, 0))
            ]),
            Fixture.recordBytes("ADDN", formID: 0x802, fields: [
                ("EDID", Fixture.zstring("Sparks")), ("MODL", Fixture.zstring("fx/sparks.nif")),
                ("DATA", Fixture.u32(1)), ("DNAM", Fixture.u16(40, 0))
            ])
        ])
        return EffectRecordStore(plugins: [(name: plugin, file: file)])
    }

    static func key(_ objectID: UInt32) -> ReferenceKey {
        .plugin(name: plugin.lowercased(), objectID: objectID)
    }

    @Test func theCatalogListsEffectRecordsByName() throws {
        let catalog = try EffectCatalog(records: Self.records())
        #expect(catalog.entries.map(\.name) == ["GlowArt", "GlowEffect", "Sparks"])
        #expect(catalog.entry(named: "GlowEffect")?.kind == .visualEffect)
        #expect(catalog.entry(named: "Missing") == nil)
    }

    @Test func aVisualEffectTakesItsArtModel() throws {
        let records = try Self.records()
        #expect(records.visualEffectSpec(Self.key(0x801))?.artModel == "fx/glow.nif")
        #expect(records.visualEffectSpec(Self.key(0x802))?.artModel == "fx/sparks.nif")
        let entry = try #require(EffectCatalog(records: records).entry(named: "GlowEffect"))
        #expect(records.details(of: entry) == [
            "Kind: Visual effect",
            "Art: GlowArt",
            "Shader: none"
        ])
    }

    @Test func theCoordinatorAttachesShowsAndClearsDebugEffects() throws {
        let effects = EffectsCoordinator()
        try effects.wire(records: Self.records(), meshes: nil)
        #expect(effects
            .attach(Self.key(0x801), to: .actor(.player), cause: .debug, duration: nil) != nil)
        effects.showModel("fx/blast.nif", at: .zero, cause: .explosion)
        #expect(effects.visualEffects.instances.count == 2)
        effects.removeAll(cause: .debug)
        #expect(effects.visualEffects.instances.map(\.cause) == [.explosion])
        effects.detachAll(from: .player)
        #expect(effects.visualEffects.instances.count == 1)
    }

    @Test func theReadoutListsLiveEffects() {
        var runtime = VisualEffectRuntime()
        let spec = VisualEffectSpec(name: "Glow", artModel: "fx/glow.nif", membrane: nil)
        runtime.attach(spec, to: .actor(.player), cause: .debug, duration: 2)
        let text = EffectsReadout.visualEffects(VisualEffectSnapshot(
            instances: runtime.instances, attachedTotal: 1, failedModels: 0, lastSpellHit: "none"
        ))
        #expect(text.contains("Effects: 1 live · 1 attached · 0 bad models"))
        #expect(text.contains("Glow on player, 2.00 s left"))
    }

    @Test func theImageSpaceReadoutNamesTheBaseline() {
        var state = ImageSpaceState()
        state.passEnabled = false
        let text = EffectsReadout.imageSpace(state)
        #expect(text.hasPrefix("Baseline: none"))
        #expect(text.contains("Saturation 1.00 · brightness 1.00 · contrast 1.00"))
        #expect(text.contains("Pass: off"))
    }
}
