// The difference picture and the PNG round trip with a resize.

import Foundation
@testable import OpenSkyRenderResources
import Testing

struct TexturePixelsDifferenceTests {
    @Test func differenceIsTheScaledAbsoluteErrorWithOpaqueAlpha() throws {
        let reference = TexturePixels(width: 2, height: 1, rgba: [10, 200, 0, 0, 5, 5, 5, 9])
        let candidate = TexturePixels(width: 2, height: 1, rgba: [20, 100, 0, 255, 5, 5, 5, 9])
        let picture = try TexturePixels.difference(reference: reference, candidate: candidate)
        #expect(picture.rgba == [40, 255, 0, 255, 0, 0, 0, 255])
    }

    @Test func differentSizesThrow() {
        let one = TexturePixels(width: 1, height: 1, rgba: [0, 0, 0, 255])
        let two = TexturePixels(width: 2, height: 1, rgba: [UInt8](repeating: 0, count: 8))
        #expect(throws: TextureImageDifferenceError.self) {
            try TexturePixels.difference(reference: one, candidate: two)
        }
    }

    @Test func pngReadsBackScaledToTheAskedSize() throws {
        let red = TexturePixels(
            width: 4, height: 2,
            rgba: Array([[UInt8]](repeating: [255, 0, 0, 255], count: 8).joined())
        )
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try FrameScreenshot.write(image: #require(red.cgImage()), to: url)
        let half = try TexturePixels(contentsOf: url, size: (width: 2, height: 1))
        #expect(half.width == 2 && half.height == 1)
        #expect(Array(half.rgba.prefix(4)) == [255, 0, 0, 255])
    }
}
