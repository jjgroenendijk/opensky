// Cutting the large levels off a texture's bytes, so a streamed texture uploads only
// the levels it keeps.

import Foundation
import OpenSkyAssetCache
import OpenSkyRendering
import Testing

struct TextureLevelBytesTests {
    /// 8 x 8 RGBA with four levels; each byte holds its level number.
    private let ready = ReadyTexture(
        format: .rgba8, width: 8, height: 8, mipCount: 4,
        bytes: Data([8, 4, 2, 1].enumerated().flatMap { level, side in
            [UInt8](repeating: UInt8(level), count: side * side * 4)
        })
    )

    @Test func theCutKeepsTheSmallLevels() {
        let levels = TextureLevelBytes.levels(of: ready, from: 2)
        #expect(levels.levels == 2 ..< 4)
        #expect(levels.ready.width == 2)
        #expect(levels.ready.mipCount == 2)
        #expect(levels.bytes(level: 2) == Data(repeating: 2, count: 16))
        #expect(levels.bytes(level: 3) == Data(repeating: 3, count: 4))
        #expect(levels.bytesPerRow(level: 2) == 8)
    }

    @Test func theCutClampsToTheSmallestLevel() {
        #expect(TextureLevelBytes.levels(of: ready, from: 9).levels == 3 ..< 4)
        #expect(TextureLevelBytes.levels(of: ready, from: -1).levels == 0 ..< 4)
    }
}
