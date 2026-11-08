// BSPSysSimpleColorModifier decode and its colour ramp, over synthetic in-code
// payloads (NIFParticleFixture). Layout: docs/formats/nif-particles.md.

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct NIFParticleColourTests {
    /// The colour modifier holds colour 1, blends to colour 2, holds it, then
    /// blends to colour 3, while alpha fades in at birth and out before death.
    @Test func simpleColourModifierDecodesItsRamp() throws {
        let colours: [SIMD4<Float>] = [SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0.4), SIMD4(0, 0, 1, 0)]
        let block = NIFParticleFixture.simpleColourModifier(
            base: NIFParticleFixture.modifierBase(),
            fades: SIMD2(0.1, 0.25), stops: SIMD4(0.1, 0.4, 0.5, 1), colours: colours
        )
        let system = NIFParticleFixture.particleSystemSSE(dataRef: 2, modifierRefs: [3])
        let file = try NIFFile(data: NIFFixture.file(
            blocks: [
                NIFFixture.Block("NiNode", NIFFixture.niNode(children: [1])),
                NIFFixture.Block("NiParticleSystem", system),
                NIFFixture.Block("NiPSysData", NIFParticleFixture.psysData(maxParticles: 4)),
                NIFFixture.Block("BSPSysSimpleColorModifier", block)
            ],
            roots: [0]
        ))
        let modifier = try #require(file.particleSystems().first?.modifiers.first)
        guard case let .simpleColour(ramp) = modifier.kind else {
            Issue.record("expected a colour ramp, got \(modifier.kind)")
            return
        }
        #expect(ramp.colours == colours)
        #expect(ramp.colour(at: 0) == SIMD4(1, 0, 0, 0))
        #expect(ramp.colour(at: 0.45) == colours[1])
        let blended = ramp.colour(at: 0.25)
        #expect(abs(blended.x - 0.5) < 1e-5 && abs(blended.y - 0.5) < 1e-5)
        #expect(abs(ramp.colour(at: 0.75).w - 0.2) < 1e-5)
        #expect(abs(ramp.colour(at: 1).w) < 1e-5)
    }
}
