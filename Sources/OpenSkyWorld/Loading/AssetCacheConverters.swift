// The converters one cache build runs, picked by preset. The app and openskycli
// build with the same set, so their caches match.

import Foundation
import Metal
import OpenSkyAssetCache
import OpenSkyAudio
import OpenSkyRendering

nonisolated public enum AssetCacheConvertersError: Error, Equatable {
    case metalUnavailable
}

nonisolated public enum AssetCacheConverters {
    /// A preset with ASTC textures needs a Metal device to decode the shipped blocks.
    public static func make(
        preset: AssetQualityPreset, device: (any MTLDevice)?, library: (any MTLLibrary)?
    ) throws -> [any AssetConverting] {
        var converters: [any AssetConverting] = [
            ReadyMeshConverter(), ReadyCollisionConverter()
        ]
        let needsASTC = preset.values.textures.values.contains { $0 != .shipped }
        if needsASTC {
            guard let device, let library else { throw AssetCacheConvertersError.metalUnavailable }
            try converters.insert(ASTCTextureConverter(device: device, library: library), at: 0)
        } else {
            converters.insert(ShippedTextureConverter(), at: 0)
        }
        return converters
    }

    /// The converters for `preset` on the system GPU, with the bundled shaders.
    public static func make(preset: AssetQualityPreset) throws -> [any AssetConverting] {
        let device = MTLCreateSystemDefaultDevice()
        return try make(preset: preset, device: device, library: device?.makeDefaultLibrary())
    }

    /// Converters limited to `kinds`, for a partial build.
    public static func filter(
        _ converters: [any AssetConverting], kinds: Set<AssetCacheKind>
    ) -> [any AssetConverting] {
        kinds.isEmpty ? converters : converters.filter { kinds.contains($0.kind) }
    }
}
