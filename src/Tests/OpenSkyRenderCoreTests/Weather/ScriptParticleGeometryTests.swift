// A script's `SPGD` over the weather: the fade in, the fade out, and the type.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyRenderCore
import Testing

struct ScriptParticleGeometryTests {
    @Test func snowFadesInAndOutOverTheWeather() throws {
        let snow = try PrecipitationTuningTests.geometry(
            type: 1, gravity: 1, size: [1, 1], density: 1
        )
        var overlay = ScriptParticleGeometry()
        overlay.apply(snow, fadeIn: 2)
        overlay.advance(1)
        #expect(overlay.strength == 0.5)
        let rain = PrecipitationState(rainIntensity: 0.7, snowIntensity: 0.2)
        #expect(overlay.adding(to: rain) == PrecipitationState(
            rainIntensity: 0.7, snowIntensity: 0.5
        ))
        overlay.advance(5)
        overlay.remove(fadeOut: 0)
        #expect(overlay.record == nil)
        #expect(overlay.adding(to: rain) == rain)
    }

    @Test func rainAppliedAtOnceShowsFully() throws {
        let rain = try PrecipitationTuningTests.geometry(
            type: 0, gravity: 1, size: [1, 1], density: 1
        )
        var overlay = ScriptParticleGeometry()
        overlay.apply(rain, fadeIn: -3)
        #expect(overlay.adding(to: .none) == PrecipitationState(
            rainIntensity: 1, snowIntensity: 0
        ))
    }
}
