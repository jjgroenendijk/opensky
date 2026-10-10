// ASTC textures stream like BC ones: Metal makes a placement-sparse texture for
// each block size, and its tiles hold 32 x 32 blocks at the 16 KB page size.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyRendering
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.gpu))
struct SparseASTCTextureTests {
    nonisolated private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.apple6) else { return nil }
        return device
    }()

    nonisolated private static var hasDevice: Bool {
        device != nil
    }

    @Test(.enabled(if: Self.hasDevice), arguments: [
        (ReadyTextureFormat.astc4x4, 128), (.astc5x5, 160), (.astc6x6, 192), (.astc8x8, 256)
    ])
    func anASTCTextureStreams(format: ReadyTextureFormat, tileSide: Int) throws {
        let device = try #require(Self.device)
        var settings = TextureStreamingLoadSettings()
        settings.enabled = true
        let ready = ReadyTexture(
            format: format,
            width: 2048,
            height: 2048,
            mipCount: 12,
            bytes: Data()
        )
        let sparse = try #require(TextureLoader(device: device).sparseTexture(
            ready: ready, usage: .color, label: "astc", settings: settings
        ))
        #expect(sparse.layout.tileSize == SIMD2(tileSide, tileSide))
        #expect(sparse.layout.firstLevelInTail > 0)
    }
}
