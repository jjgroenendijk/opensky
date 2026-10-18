// The converters one conversion runs, picked by texture output. The app and openskycli
// build with the same set, so their caches match.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyRendering

nonisolated public enum AssetCacheConvertersError: Error, Equatable {
    case metalUnavailable
}

nonisolated public enum AssetCacheConverters {
    /// An output that re-encodes textures needs a Metal device to decode the shipped blocks.
    public static func make(
        textureOutput: AssetTextureOutput, device: (any MTLDevice)?, library: (any MTLLibrary)?
    ) throws -> [any AssetConverting] {
        var converters: [any AssetConverting] = [
            ReadyMeshConverter(), ReadyCollisionConverter()
        ]
        if textureOutput.needsEncoder {
            guard let device, let library else { throw AssetCacheConvertersError.metalUnavailable }
            try converters.insert(ASTCTextureConverter(device: device, library: library), at: 0)
        } else {
            converters.insert(ShippedTextureConverter(), at: 0)
        }
        return converters
    }

    /// The converters for `textureOutput` on the system GPU, with the bundled shaders.
    public static func make(textureOutput: AssetTextureOutput) throws -> [any AssetConverting] {
        let device = MTLCreateSystemDefaultDevice()
        return try make(
            textureOutput: textureOutput,
            device: device,
            library: device?.makeDefaultLibrary()
        )
    }
}
