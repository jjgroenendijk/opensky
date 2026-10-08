// Image difference on synthetic pixels: PSNR per channel group and the mean
// normal angle of a normal map.

@testable import OpenSkyRendering
import Testing

struct TextureImageDifferenceTests {
    private func image(_ pixel: [UInt8]) -> TexturePixels {
        TexturePixels(width: 1, height: 1, rgba: pixel)
    }

    @Test func alphaErrorLowersOnlyTheAlphaPSNR() throws {
        let difference = try TextureImageDifference.compare(
            reference: image([10, 20, 30, 255]), candidate: image([10, 20, 30, 0]), normals: false
        )
        #expect(difference.rgbPSNR == TextureImageDifference.losslessPSNR)
        #expect(difference.alphaPSNR == 0)
        #expect(difference.maxChannelError == 255)
        #expect(difference.meanNormalAngleDegrees == nil)
    }

    @Test func aNormalTurnedFromZToXIsNinetyDegreesOff() throws {
        let difference = try TextureImageDifference.compare(
            reference: image([128, 128, 255, 255]), candidate: image([255, 128, 128, 255]),
            normals: true
        )
        let angle = try #require(difference.meanNormalAngleDegrees)
        #expect(abs(angle - 90) < 1)
    }
}
