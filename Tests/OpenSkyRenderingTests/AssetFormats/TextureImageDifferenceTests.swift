// Image difference over synthetic RGBA8 images.

import Foundation
@testable import OpenSkyRendering
import Testing

struct TextureImageDifferenceTests {
    private static func image(_ pixels: [[UInt8]]) -> TexturePixels {
        TexturePixels(width: pixels.count, height: 1, rgba: pixels.flatMap(\.self))
    }

    @Test func identicalImagesAreLossless() throws {
        let image = Self.image([[10, 20, 30, 255], [200, 100, 0, 128]])
        let difference = try TextureImageDifference.compare(
            reference: image, candidate: image, normals: false
        )
        #expect(difference.isLossless)
        #expect(difference.rgbPSNR == TextureImageDifference.losslessPSNR)
        #expect(difference.alphaPSNR == TextureImageDifference.losslessPSNR)
        #expect(difference.meanNormalAngleDegrees == nil)
    }

    @Test func psnrFollowsTheMeanSquaredError() throws {
        let reference = Self.image([[100, 100, 100, 255]])
        let candidate = Self.image([[110, 100, 100, 255]])
        let difference = try TextureImageDifference.compare(
            reference: reference, candidate: candidate, normals: false
        )
        // One of three RGB samples is off by 10: MSE = 100 / 3.
        let expected = 10 * log10(255.0 * 255.0 / (100.0 / 3.0))
        #expect(abs(difference.rgbPSNR - expected) < 1e-9)
        #expect(difference.alphaPSNR == TextureImageDifference.losslessPSNR)
        #expect(difference.maxChannelError == 10)
    }

    @Test func normalsReportTheMeanAngle() throws {
        // +Z against +X: a right angle on one of two pixels.
        let reference = Self.image([[128, 128, 255, 255], [128, 128, 255, 255]])
        let candidate = Self.image([[128, 128, 255, 255], [255, 128, 128, 255]])
        let difference = try TextureImageDifference.compare(
            reference: reference, candidate: candidate, normals: true
        )
        let angle = try #require(difference.meanNormalAngleDegrees)
        #expect(abs(angle - 45) < 0.5)
    }

    @Test func differentSizesThrow() {
        let small = Self.image([[0, 0, 0, 0]])
        let large = Self.image([[0, 0, 0, 0], [0, 0, 0, 0]])
        #expect(throws: TextureImageDifferenceError.self) {
            try TextureImageDifference.compare(reference: small, candidate: large, normals: false)
        }
    }
}
