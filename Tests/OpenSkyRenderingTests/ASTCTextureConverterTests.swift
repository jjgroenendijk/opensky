// The asset cache texture path on the GPU: a ready texture uploads to the same
// texels as its DDS, and the ASTC presets stay within their quality limits.

import EngineTesting
import FormatsTesting
import Foundation
import Metal
import OpenSkyAssetCache
@testable import OpenSkyFormatsMesh
@testable import OpenSkyRendering
import TagsTesting
import Testing

@MainActor
@Suite(.tags(.gpu))
struct ASTCTextureConverterTests {
    nonisolated private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsBCTextureCompression else { return nil }
        return device
    }()

    nonisolated private static var hasDevice: Bool {
        device != nil
    }

    private struct GPU {
        let converter: ASTCTextureConverter
        let loader: TextureLoader
        let readback: TextureReadback
    }

    private func gpu() throws -> GPU {
        let device = try #require(Self.device, "no BCn-capable Metal device")
        let library = try ShaderLibraryFixture.library(device: device)
        return try GPU(
            converter: ASTCTextureConverter(device: device, library: library),
            loader: TextureLoader(device: device),
            readback: TextureReadback(device: device, library: library)
        )
    }

    /// A smooth RGBA8 gradient, which ASTC can hold closely.
    private func gradient(size: Int) -> ReadyTexture {
        var bytes = Data(capacity: size * size * 4)
        for y in 0 ..< size {
            for x in 0 ..< size {
                bytes.append(contentsOf: [UInt8(x * 255 / size), UInt8(y * 255 / size), 128, 255])
            }
        }
        return ReadyTexture(format: .rgba8, width: size, height: size, mipCount: 1, bytes: bytes)
    }

    @Test(.enabled(if: Self.hasDevice), arguments: [DDSPixelFormat.bc1, .bc3, .xrgb8888, .rgba8888])
    func readyUploadMatchesDDSUpload(format: DDSPixelFormat) throws {
        let gpu = try gpu()
        let loader = gpu.loader
        let readback = gpu.readback
        let dds = try DDSFile(data: DDSFixture.file(
            format: format,
            width: 16,
            height: 8,
            mipCount: 3
        ))
        let direct = try loader.upload(dds: dds, usage: .color, label: "dds")
        let ready = try loader.upload(ready: ReadyTexture(dds: dds), usage: .color, label: "ready")
        #expect(ready.pixelFormat == direct.pixelFormat)
        for level in 0 ..< 3 {
            #expect(try readback.pixels(of: ready, level: level) == readback.pixels(
                of: direct,
                level: level
            ))
        }
    }

    @Test(.enabled(if: Self.hasDevice))
    func highestQualityKeepsShippedBytes() throws {
        let converter = try gpu().converter
        let bytes = DDSFixture.file(format: .bc1, width: 8, height: 8, mipCount: 2)
        let converted = try converter.convert(
            path: "textures\\a_n.dds",
            bytes: bytes,
            preset: .highestQuality
        )
        #expect(try converted == ReadyTextureCodec.encode(ReadyTexture(dds: DDSFile(data: bytes))))
    }

    @Test(.enabled(if: Self.hasDevice), arguments: [
        (ReadyTextureFormat.astc4x4, 40.0), (.astc6x6, 30.0), (.astc8x8, 30.0)
    ])
    func astcStaysWithinPresetLimit(format: ReadyTextureFormat, minimumPSNR: Double) throws {
        let gpu = try gpu()
        let converter = gpu.converter
        let loader = gpu.loader
        let readback = gpu.readback
        let source = gradient(size: 64)
        let encoded = try converter.encode(source, as: format)
        #expect(encoded.format == format)
        let reference = try converter.decodedLevels(of: source)[0]
        let uploaded = try loader.upload(ready: encoded, usage: .data, label: "astc")
        let candidate = try readback.pixels(of: uploaded, level: 0)
        let difference = try TextureImageDifference.compare(
            reference: reference, candidate: candidate, normals: false
        )
        #expect(difference.rgbPSNR >= minimumPSNR)
    }
}
