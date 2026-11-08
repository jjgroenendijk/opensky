@testable import OpenSkyRenderCore
@testable import OpenSkyRendering
import Testing

struct UpscalingReadoutTests {
    @Test
    func aScalerStillBuildingSaysTheSceneDrawsAtFullSize() {
        let status = UpscaleStatus(upscaler: .temporal, historyResets: 2, buildingScaler: true)
        #expect(RenderPerformanceReadout.upscalingText(
            scale: RenderScale(percent: 67), status: status
        ) == """
        Upscaling: 67%, temporal
        Building the MetalFX scaler; the scene draws at full size until it is ready
        History resets: 2
        """)
    }

    @Test
    func aBuildingFlagWithUpscalingOffReadsOff() {
        let status = UpscaleStatus(buildingScaler: true)
        #expect(RenderPerformanceReadout.upscalingText(scale: .off, status: status)
            .hasPrefix("Upscaling: off"))
    }
}
