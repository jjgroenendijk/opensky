// The game's shadow distance and map size, made safe for the shadow pass.

@testable import OpenSkyRenderCore
import Testing

struct ShadowSettingsTests {
    @Test(arguments: [
        (0.0, 2048), (4096.0, 4096), (3000.0, 2048), (100.0, 512), (16384.0, 16384),
        (10000.0, 8192), (1e6, 16384), (Double.nan, 2048)
    ])
    func resolutionIsAPowerOfTwoInRange(value: Double, expected: Int) {
        #expect(ShadowSettings(distance: 0, resolution: value).resolution == expected)
    }

    @Test
    func zeroDistanceKeepsTheRendererRange() {
        #expect(ShadowSettings(distance: 0, resolution: 0).distance == nil)
        #expect(ShadowSettings(distance: 8000, resolution: 0).distance == 8000)
        #expect(ShadowSettings(distance: -1, resolution: 0).distance == nil)
    }
}
