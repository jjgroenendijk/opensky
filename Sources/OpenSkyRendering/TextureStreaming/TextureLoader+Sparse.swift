// Creates the placement-sparse textures that stream their levels. The texture has no
// memory until the frame maps tiles to it. See docs/rendering/texture-streaming.md.

import Metal
import OpenSkyAssetCache

nonisolated extension TextureLoader {
    /// A sparse texture for `ready`, or nil when it is too small to gain from streaming,
    /// or the GPU cannot make it. Nil means: upload it the normal way.
    public func sparseTexture(
        ready: ReadyTexture, usage: TextureUsage, label: String,
        settings: TextureStreamingLoadSettings
    ) -> (texture: MTLTexture, layout: SparseTextureLayout)? {
        guard
            settings.enabled, ready.mipCount > 1,
            max(ready.width, ready.height) >= settings.minimumSize,
            !ready.format.isASTC,
            device.supportsFamily(.apple6)
        else { return nil }
        let pixelFormat = Self.pixelFormat(for: ready.format, usage: usage)
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = pixelFormat
        descriptor.width = ready.width
        descriptor.height = ready.height
        descriptor.mipmapLevelCount = ready.mipCount
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        descriptor.placementSparsePageSize = settings.pageSize
        guard
            let texture = device.makeTexture(descriptor: descriptor),
            texture.sparseTextureTier == .tier2,
            let firstInTail = texture.firstMipmapInTail,
            let tailBytes = texture.tailSizeInBytes
        else { return nil }
        texture.label = label
        let tileBytes = device.sparseTileSizeInBytes(sparsePageSize: settings.pageSize)
        let tile = device.sparseTileSize(
            textureType: .type2D, pixelFormat: pixelFormat, sampleCount: 1,
            sparsePageSize: settings.pageSize
        )
        let layout = SparseTextureLayout(
            size: SIMD2(ready.width, ready.height), mipCount: ready.mipCount,
            tileSize: SIMD2(tile.width, tile.height),
            tail: (firstInTail, (tailBytes + tileBytes - 1) / tileBytes)
        )
        // A texture that lives in its tail alone gains nothing.
        guard layout.firstLevelInTail > 0 else { return nil }
        return (texture, layout)
    }
}
