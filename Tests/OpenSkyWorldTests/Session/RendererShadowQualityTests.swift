// Sun-shadow integration: per-cascade caster culling via
// `lastShadowDrawStats`, the quality tiers, and CPU timing. Uses
// ShadowSceneFixture. Needs Metal 4.

import Foundation
import Metal
@testable import OpenSkyRendering
import OpenSkyWorldFixtures
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct RendererShadowQualityTests {
    private static var hasMetal4Device: Bool {
        ShadowSceneFixture.hasMetal4Device
    }

    private static let width = ShadowSceneFixture.width
    private static let height = ShadowSceneFixture.height

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func perInstanceCullingDropsCastersOutsideCascades() throws {
        let device = try #require(ShadowSceneFixture.device)
        let renderer = try ShadowSceneFixture.makeRenderer(
            device: device,
            scene: ShadowSceneFixture.cullingScene(device: device)
        )
        renderer.sunShadowsEnabled = true
        renderer.shadowQuality = .high
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)

        let stats = renderer.lastShadowDrawStats
        #expect(stats.cascadesRendered == 3, "high quality renders 3 cascades")
        #expect(stats.drawnInstances > 0, "near casters must render into the cascades")
        #expect(
            stats.culledInstances > 0,
            "the far tower instance must be culled from every cascade"
        )
        // Drawn is strictly below the naive every-instance-every-cascade count
        // (3 instances x 3 cascades = 9): proves per-instance culling ran.
        #expect(stats.drawnInstances < 9, "per-instance culling must skip the far tower")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func qualityOffMatchesDisabledBaseline() throws {
        let device = try #require(ShadowSceneFixture.device)

        let offRenderer = try ShadowSceneFixture.makeRenderer(device: device)
        offRenderer.shadowQuality = .off
        _ = try offRenderer.renderOffscreen(width: Self.width, height: Self.height)
        let off = try ShadowSceneFixture.readPixels(
            texture: offRenderer.renderOffscreen(width: Self.width, height: Self.height)
        )
        #expect(offRenderer.lastShadowDrawStats == ShadowDrawStats(), "off encodes no shadows")

        let baseline = try ShadowSceneFixture.makeRenderer(device: device)
        baseline.sunShadowsEnabled = false
        _ = try baseline.renderOffscreen(width: Self.width, height: Self.height)
        let never = try ShadowSceneFixture.readPixels(
            texture: baseline.renderOffscreen(width: Self.width, height: Self.height)
        )

        var differences = 0
        for index in off.indices where off[index] != never[index] {
            differences += 1
        }
        #expect(differences == 0, "quality .off left \(differences) pixels off the baseline")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func lowAndHighQualityBothDarkenReceiver() throws {
        let device = try #require(ShadowSceneFixture.device)

        let offRenderer = try ShadowSceneFixture.makeRenderer(device: device)
        offRenderer.shadowQuality = .off
        let off = try ShadowSceneFixture.readPixels(
            texture: offRenderer.renderOffscreen(width: Self.width, height: Self.height)
        )

        for quality in [ShadowQuality.low, .high] {
            let renderer = try ShadowSceneFixture.makeRenderer(device: device)
            renderer.shadowQuality = quality
            let shaded = try ShadowSceneFixture.readPixels(
                texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
            )
            let darker = ShadowSceneFixture.darkerPixelCount(on: shaded, off: off)
            #expect(darker > 50, "\(quality) cast no visible shadow (\(darker) darkened)")
        }
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func qualityRendersAreDeterministic() throws {
        let device = try #require(ShadowSceneFixture.device)
        for quality in [ShadowQuality.low, .high] {
            let renderer = try ShadowSceneFixture.makeRenderer(device: device)
            renderer.shadowQuality = quality
            let first = try ShadowSceneFixture.readPixels(
                texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
            )
            let second = try ShadowSceneFixture.readPixels(
                texture: renderer.renderOffscreen(width: Self.width, height: Self.height)
            )
            var differences = 0
            for index in first.indices where first[index] != second[index] {
                differences += 1
            }
            #expect(differences == 0, "\(quality) render not deterministic (\(differences) px)")
        }
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func shadowTimingMetricIsRecorded() throws {
        let device = try #require(ShadowSceneFixture.device)
        let renderer = try ShadowSceneFixture.makeRenderer(device: device)
        renderer.sunShadowsEnabled = true
        renderer.shadowQuality = .high
        _ = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        #expect(renderer.lastShadowUpdateMS > 0, "encodeShadowPass CPU time was not measured")
    }
}
