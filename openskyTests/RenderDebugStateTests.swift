// Render debug views + layer isolation (issue #144).
//
// The CPU half pins the two things that would otherwise fail silently: the
// Swift enums drifting away from the C enums the shaders read (a wrong colour
// on screen is not a test failure), and the composition rule between the layer
// mask and the subsystem enables.
//
// The device-gated half is the evidence that the mask reaches the GPU: draw-stat
// deltas for the scene and shadow passes, and pixel proof that a debug channel
// changes the frame while an offscreen render still renders the shipping one.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RenderDebugStateTests {
    // MARK: - Shader contract

    @Test
    func debugModeRawValuesMatchTheShaderEnum() {
        #expect(RenderDebugMode.off.rawValue == UInt32(DebugViewMode.off.rawValue))
        #expect(RenderDebugMode.wireframe.rawValue == UInt32(DebugViewMode.wireframe.rawValue))
        #expect(
            RenderDebugMode.worldNormals.rawValue == UInt32(DebugViewMode.worldNormals.rawValue)
        )
        #expect(
            RenderDebugMode.textureCoordinates.rawValue
                == UInt32(DebugViewMode.textureCoordinates.rawValue)
        )
        #expect(RenderDebugMode.mipLevel.rawValue == UInt32(DebugViewMode.mipLevel.rawValue))
        #expect(
            RenderDebugMode.shadowCascade.rawValue == UInt32(DebugViewMode.shadowCascade.rawValue)
        )
        #expect(
            RenderDebugMode.layerCategory.rawValue == UInt32(DebugViewMode.layerCategory.rawValue)
        )
        #expect(RenderDebugMode.allCases.count == 7)
    }

    @Test
    func layerRawValuesMatchTheShaderEnum() {
        #expect(RenderLayer.statics.rawValue == UInt32(RenderLayerBit.statics.rawValue))
        #expect(RenderLayer.actors.rawValue == UInt32(RenderLayerBit.actors.rawValue))
        #expect(RenderLayer.distantLOD.rawValue == UInt32(RenderLayerBit.distantLOD.rawValue))
        #expect(RenderLayer.terrain.rawValue == UInt32(RenderLayerBit.terrain.rawValue))
        #expect(RenderLayer.water.rawValue == UInt32(RenderLayerBit.water.rawValue))
        #expect(RenderLayer.sky.rawValue == UInt32(RenderLayerBit.sky.rawValue))
        #expect(RenderLayer.grass.rawValue == UInt32(RenderLayerBit.grass.rawValue))
        #expect(RenderLayer.particles.rawValue == UInt32(RenderLayerBit.particles.rawValue))
    }

    @Test
    func everyLayerIsListedOnceInAllAndInOrdered() {
        #expect(RenderLayer.ordered.count == 8)
        #expect(Set(RenderLayer.ordered).count == 8)
        #expect(RenderLayer.ordered.reduce(into: RenderLayer()) { $0.insert($1) } == .all)
        #expect(RenderLayer.all.rawValue.nonzeroBitCount == 8)
    }

    // MARK: - Solo derivation

    @Test
    func soloIsDerivedFromTheMaskRatherThanStored() {
        #expect(RenderLayer.all.soloedLayer == nil)
        #expect(RenderLayer().soloedLayer == nil)
        #expect(RenderLayer.terrain.soloedLayer == .terrain)
        #expect(RenderLayer([.terrain, .water]).soloedLayer == nil)
    }

    // MARK: - Composition rule

    @Test
    func aFeatureSwitchAndTheViewFilterCompose() {
        let all = RenderLayer.all
        #expect(
            RenderLayerPolicy.effective(
                mask: all, grassEnabled: true, particlesEnabled: true, precipitationEnabled: true
            ) == all
        )
        #expect(
            !RenderLayerPolicy.effective(
                mask: all, grassEnabled: false, particlesEnabled: true, precipitationEnabled: true
            ).contains(.grass)
        )
        // Both particle sources must be off before the shared layer goes.
        #expect(
            RenderLayerPolicy.effective(
                mask: all, grassEnabled: true, particlesEnabled: false, precipitationEnabled: true
            ).contains(.particles)
        )
        #expect(
            !RenderLayerPolicy.effective(
                mask: all, grassEnabled: true, particlesEnabled: false, precipitationEnabled: false
            ).contains(.particles)
        )
    }

    @Test
    func theViewFilterCannotTurnASwitchedOffSubsystemBackOn() {
        let effective = RenderLayerPolicy.effective(
            mask: .grass, grassEnabled: false, particlesEnabled: true, precipitationEnabled: true
        )
        #expect(effective.isEmpty)
    }

    @Test
    func aHiddenLayerStaysHiddenWhenItsSubsystemIsOn() {
        let effective = RenderLayerPolicy.effective(
            mask: RenderLayer.all.subtracting(.grass),
            grassEnabled: true,
            particlesEnabled: true,
            precipitationEnabled: true
        )
        #expect(!effective.contains(.grass))
        #expect(effective.contains(.particles))
    }

    // MARK: - Readout

    @Test
    func readoutNamesTheSoloedLayerAndTheSuppressedOnes() {
        let snapshot = RenderDebugControlSnapshot(
            mode: .wireframe,
            layers: .grass,
            effectiveLayers: RenderLayer(),
            stats: SceneDrawStats(),
            shadowStats: ShadowDrawStats()
        )
        #expect(RenderDebugReadout.modeText(for: snapshot) == "View: Wireframe")
        #expect(RenderDebugReadout.layerText(for: snapshot) == "Layers: solo Grass")
        #expect(RenderDebugReadout.suppressedText(for: snapshot)?.contains("Grass") == true)
    }

    @Test
    func defaultReadoutReportsAllLayersAndNoSuppression() {
        let snapshot = RenderDebugControlSnapshot(
            mode: .off,
            layers: .all,
            effectiveLayers: .all,
            stats: SceneDrawStats(),
            shadowStats: ShadowDrawStats()
        )
        #expect(RenderDebugReadout.layerText(for: snapshot) == "Layers: all layers")
        #expect(RenderDebugReadout.suppressedText(for: snapshot) == nil)
    }

    @Test
    func defaultStateIsProduction() {
        #expect(RenderDebugState().isDefault)
        #expect(!RenderDebugState().isDebugViewActive)
        #expect(RenderDebugState(mode: .wireframe, layers: .all).isDebugViewActive)
    }
}
