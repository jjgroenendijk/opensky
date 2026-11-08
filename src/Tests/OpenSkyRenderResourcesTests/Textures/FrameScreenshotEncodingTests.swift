// A half-float frame holds linear colour; the screenshot encodes it to sRGB bytes.

@testable import OpenSkyRenderResources
import Testing

struct FrameScreenshotEncodingTests {
    @Test func linearValuesEncodeToSRGB() {
        #expect(FrameScreenshot.srgbByte(0) == 0)
        #expect(FrameScreenshot.srgbByte(1) == 255)
        #expect(FrameScreenshot.srgbByte(0.215_861) == 128)
    }

    @Test func valuesOutsideTheRangeClamp() {
        #expect(FrameScreenshot.srgbByte(-2) == 0)
        #expect(FrameScreenshot.srgbByte(4) == 255)
    }

    @Test func rgbaBecomesBGRA() {
        let bytes = FrameScreenshot.bgraBytes(linearRGBA: [1, 0, 0, 1, 0, 0, 1, 0.5])
        #expect(bytes == [0, 0, 255, 255, 255, 0, 0, 128])
    }
}
