// The converters one conversion runs, picked by texture output, and the live asset
// cache environment. The app and openskycli build with the same set, so their caches match.

import Foundation
public import Metal
public import OpenSkyAssetCache
import OpenSkyGameData
public import OpenSkyLoading
import OpenSkyPhysics
import OpenSkyRenderResources
import OpenSkyShaders

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
            library: device.map { try ShaderLibrary.make(device: $0) }
        )
    }
}

extension AssetCacheCoordinator.Environment {
    /// The located install and the converters on the system GPU.
    public static let live = Self(
        locate: {
            let root = try GameDataLocator.locate()
            return (VirtualFileSystem(root: root), root.installURL)
        },
        makeConverters: { try AssetCacheConverters.make(textureOutput: $0) }
    )
}
