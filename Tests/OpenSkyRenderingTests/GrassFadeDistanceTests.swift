// The game's grass fade start sets the grass draw distance.

@testable import OpenSkyRendering
import Testing

struct GrassFadeDistanceTests {
    @Test
    func fadeStartsAtTheGameDistance() throws {
        let distance = try #require(GrassRenderPolicy.drawDistance(fadeStart: 7000))
        #expect(abs(distance * GrassRenderPolicy.fadeStartShare - 7000) < 0.5)
    }

    @Test
    func missingOrHugeValuesStayInRange() {
        #expect(GrassRenderPolicy.drawDistance(fadeStart: 0) == nil)
        #expect(GrassRenderPolicy.drawDistance(fadeStart: .infinity) == nil)
        #expect(GrassRenderPolicy.drawDistance(fadeStart: 1e9) == GrassRenderPolicy
            .maximumDrawDistance)
        #expect(GrassRenderPolicy.drawDistance(fadeStart: 10) == GrassRenderPolicy
            .minimumDrawDistance)
    }
}
