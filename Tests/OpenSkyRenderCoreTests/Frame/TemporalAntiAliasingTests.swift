// bUseTAA picks the temporal scaler at full size only while the render scale is off.

@testable import OpenSkyRenderCore
import Testing

struct TemporalAntiAliasingTests {
    @Test func offScaleRunsTheTemporalScalerAtFullSize() {
        let result = RenderScale.resolve(.off, upscaler: .spatial, temporalAntiAliasing: true)
        #expect(result.scale == .native)
        #expect(result.upscaler == .temporal)
    }

    @Test func aChosenScaleWins() {
        let chosen = RenderScale(percent: 67)
        let result = RenderScale.resolve(chosen, upscaler: .spatial, temporalAntiAliasing: true)
        #expect(result.scale == chosen)
        #expect(result.upscaler == .spatial)
    }

    @Test func offOptionKeepsTheScaleOff() {
        let result = RenderScale.resolve(.off, upscaler: .temporal, temporalAntiAliasing: false)
        #expect(result.scale == .off)
    }
}
