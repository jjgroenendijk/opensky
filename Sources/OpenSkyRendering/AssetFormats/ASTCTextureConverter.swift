// The texture converter of asset optimisation. A texture kept shipped is stored
// as it is. One with a quality target is decoded by the GPU once, then each
// smaller ASTC format is encoded, decoded, and measured until one meets the
// target. The GPU decode is the reference, because it is what the renderer shows.
// See docs/engine/asset-cache.md, "Texture quality".

import Foundation
import Metal
import OpenSkyAssetCache
import Synchronization

nonisolated public final class ASTCTextureConverter: AssetConverting, Sendable {
    private struct Decoder {
        let loader: TextureLoader
        let readback: TextureReadback
    }

    /// The GPU decode is serialized; the astcenc encode of different files runs in parallel.
    private let decoder: Mutex<Decoder>

    public init(device: MTLDevice, library: MTLLibrary) throws {
        decoder = try Mutex(Decoder(
            loader: TextureLoader(device: device),
            readback: TextureReadback(device: device, library: library)
        ))
    }

    public var kind: AssetCacheKind {
        .texture
    }

    public var version: UInt32 {
        AssetConverterVersion.texture
    }

    public func accepts(path: String) -> Bool {
        path.hasSuffix(".dds")
    }

    public func convert(path: String, bytes: Data, output: AssetTextureOutput) throws -> Data? {
        guard let shipped = try ReadyTexture.shipped(dds: bytes) else { return nil }
        let source = shipped.keepingLevels(fittingWithin: output.maximumSide)
        return try ReadyTextureCodec.encode(convert(
            source,
            plan: output.plan(forPath: path),
            path: path
        ))
    }

    /// What `source` becomes under `plan`. Every path that keeps the shipped
    /// format copies its blocks.
    public func convert(
        _ source: ReadyTexture,
        plan: TexturePlan,
        path: String
    ) throws -> ReadyTexture {
        switch plan {
        case .shipped:
            return source
        case let .forced(format):
            return format == source.format ? source : try encode(source, as: format)
        case let .search(target):
            let candidates = TextureFormatSearch.candidates(
                shipped: source.format, width: source.width, height: source.height
            )
            guard !candidates.isEmpty else { return source }
            let levels = try decodedLevels(of: source)
            guard let top = levels.first else { return source }
            let normalMap = AssetTextureClass(path: path) == .normal
            let cutout = !normalMap && top.hasTransparency
            let format = try TextureFormatSearch.pick(
                candidates, target: target, normalMap: normalMap, cutoutAlpha: cutout
            ) { try Self.measure(top, as: $0, normalMap: normalMap) }
            guard let format else { return source }
            return try Self.encode(levels, of: source, as: format)
        }
    }

    /// Every level of `texture` decoded to RGBA8 by the GPU.
    public func decodedLevels(of texture: ReadyTexture) throws -> [TexturePixels] {
        try decoder.withLock { decoder in
            let uploaded = try decoder.loader.upload(
                ready: texture,
                usage: .data,
                label: "astc-source"
            )
            let readback = decoder.readback
            return try (0 ..< texture.mipCount).map { try readback.pixels(of: uploaded, level: $0) }
        }
    }

    public func encode(
        _ texture: ReadyTexture,
        as format: ReadyTextureFormat
    ) throws -> ReadyTexture {
        try Self.encode(decodedLevels(of: texture), of: texture, as: format)
    }

    static func encode(
        _ levels: [TexturePixels], of texture: ReadyTexture, as format: ReadyTextureFormat
    ) throws -> ReadyTexture {
        let block = ASTCBlockSize(width: format.blockDimension, height: format.blockDimension)
        var bytes = Data()
        for level in levels {
            try bytes.append(ASTCEncoder.encode(level, block: block, effort: .fastest))
        }
        return ReadyTexture(
            format: format, width: texture.width, height: texture.height,
            mipCount: texture.mipCount,
            bytes: bytes
        )
    }

    /// Encodes and decodes `pixels` as `format`, and compares it with the source.
    static func measure(
        _ pixels: TexturePixels, as format: ReadyTextureFormat, normalMap: Bool
    ) throws -> TextureMeasure {
        let block = ASTCBlockSize(width: format.blockDimension, height: format.blockDimension)
        let blocks = try ASTCEncoder.encode(pixels, block: block, effort: .fastest)
        let decoded = try ASTCEncoder.decode(
            blocks,
            width: pixels.width,
            height: pixels.height,
            block: block
        )
        let difference = try TextureImageDifference.compare(
            reference: pixels, candidate: decoded, normals: normalMap
        )
        return TextureMeasure(
            rgbPSNR: difference.rgbPSNR,
            alphaPSNR: difference.alphaPSNR,
            normalDegrees: difference.meanNormalAngleDegrees
        )
    }
}

nonisolated extension TexturePixels {
    /// True when some pixel is not fully opaque, such as cut-out leaves or hair.
    public var hasTransparency: Bool {
        stride(from: 3, to: rgba.count, by: 4).contains { rgba[$0] != 0xFF }
    }
}
