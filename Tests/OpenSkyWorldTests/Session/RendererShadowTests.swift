// Cascaded sun-shadow integration: offscreen A/B renders of a synthetic ground
// and caster. Shadows darken the receiver under the caster, only ever darken,
// leave the sky alone, and disabling them matches a never-enabled baseline.
// Skips without a Metal 4 device.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
import simd
import TagsTesting
import Testing

@Suite(.tags(.gpu))
struct RendererShadowTests {
    @Test(.enabled(if: ShadowSceneFixture.hasMetal4Device))
    @MainActor
    func shadowsDarkenReceiverUnderCasterAndSpareSky() throws {
        let device = try #require(ShadowSceneFixture.device)
        let renderer = try ShadowSceneFixture.makeRenderer(device: device)

        renderer.sunShadowsEnabled = true
        let onTexture = try renderer.renderOffscreen(
            width: ShadowSceneFixture.width,
            height: ShadowSceneFixture.height
        )
        let on = ShadowSceneFixture.readPixels(texture: onTexture)

        renderer.sunShadowsEnabled = false
        let offTexture = try renderer.renderOffscreen(
            width: ShadowSceneFixture.width,
            height: ShadowSceneFixture.height
        )
        let off = ShadowSceneFixture.readPixels(texture: offTexture)

        // Shadows only ever remove the direct sun term: no channel may be
        // brighter with shadows on (allow 1 LSB of rounding).
        var brighter = 0
        var darkerPixels = 0
        for pixel in stride(from: 0, to: on.count, by: 4) {
            var pixelDarker = 0
            for channel in 0 ..< 3 {
                let onValue = Int(on[pixel + channel])
                let offValue = Int(off[pixel + channel])
                if onValue > offValue + 1 {
                    brighter += 1
                }
                pixelDarker += offValue - onValue
            }
            if pixelDarker > 40 {
                darkerPixels += 1
            }
        }
        #expect(brighter == 0, "shadows brightened \(brighter) channels — sun term math wrong")
        #expect(
            darkerPixels > 50,
            "only \(darkerPixels) pixels darkened — caster cast no visible shadow"
        )

        // The procedural sky ignores shadows entirely: the top band must be
        // bit-identical between the two renders.
        let topBand = ShadowSceneFixture.width * 6 * 4
        var skyDifferences = 0
        for index in 0 ..< topBand where on[index] != off[index] {
            skyDifferences += 1
        }
        #expect(skyDifferences == 0, "sky band changed with shadows — non-receiver was shaded")
    }

    @Test(.enabled(if: ShadowSceneFixture.hasMetal4Device))
    @MainActor
    func disabledShadowsMatchNeverEnabledBaseline() throws {
        let device = try #require(ShadowSceneFixture.device)

        // Enable shadows (populates the shadow map), then disable and render.
        let toggled = try ShadowSceneFixture.makeRenderer(device: device)
        toggled.sunShadowsEnabled = true
        _ = try toggled.renderOffscreen(
            width: ShadowSceneFixture.width,
            height: ShadowSceneFixture.height
        )
        toggled.sunShadowsEnabled = false
        let afterToggle = try ShadowSceneFixture.readPixels(
            texture: toggled.renderOffscreen(
                width: ShadowSceneFixture.width,
                height: ShadowSceneFixture.height
            )
        )

        // A renderer that never enabled shadows, matched frame count.
        let baseline = try ShadowSceneFixture.makeRenderer(device: device)
        baseline.sunShadowsEnabled = false
        _ = try baseline.renderOffscreen(
            width: ShadowSceneFixture.width,
            height: ShadowSceneFixture.height
        )
        let never = try ShadowSceneFixture.readPixels(
            texture: baseline.renderOffscreen(
                width: ShadowSceneFixture.width,
                height: ShadowSceneFixture.height
            )
        )

        var differences = 0
        for index in afterToggle.indices where afterToggle[index] != never[index] {
            differences += 1
        }
        #expect(differences == 0, "disabling shadows left \(differences) stale pixels")
    }
}
