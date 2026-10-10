// The optimised texture path on the GPU: a ready texture uploads to the same
// texels as its DDS, and the format search picks the smallest passing format.

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
            device.supportsFamily(.metal4), device.supportsBCTextureCompression
        else { return nil }
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

    /// Random texels: no ASTC block size holds them within a quality target.
    private func noise(size: Int) -> ReadyTexture {
        var generator = SystemRandomNumberGenerator()
        var bytes = Data(count: size * size * 4)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: 0 ... 255, using: &generator)
        }
        return ReadyTexture(format: .rgba8, width: size, height: size, mipCount: 1, bytes: bytes)
    }

    @Test(.enabled(if: Self.hasDevice))
    func originalKeepsShippedBytes() throws {
        let converter = try gpu().converter
        let bytes = DDSFixture.file(format: .bc1, width: 8, height: 8, mipCount: 2)
        let converted = try converter.convert(
            path: "textures\\a_n.dds",
            bytes: bytes,
            output: AssetTextureOutput(quality: .original)
        )
        #expect(try converted == ReadyTextureCodec.encode(ReadyTexture(dds: DDSFile(data: bytes))))
    }

    @Test(.enabled(if: Self.hasDevice))
    func aSmoothTextureGetsTheSmallestFormat() throws {
        let converter = try gpu().converter
        let target = try #require(TextureQuality.low.target)
        let result = try converter.convert(
            gradient(size: 512),
            plan: .search(target),
            path: "a.dds"
        )
        #expect(result.format == .astc8x8)
    }

    @Test(.enabled(if: Self.hasDevice))
    func noiseKeepsItsShippedBlocks() throws {
        let converter = try gpu().converter
        let target = try #require(TextureQuality.high.target)
        let source = noise(size: 512)
        let result = try converter.convert(source, plan: .search(target), path: "a.dds")
        #expect(result == source)
    }

    @Test(.enabled(if: Self.hasDevice))
    func aSmallTextureIsNotSearched() throws {
        let converter = try gpu().converter
        let target = try #require(TextureQuality.low.target)
        let source = gradient(size: 128)
        #expect(try converter.convert(source, plan: .search(target), path: "a.dds") == source)
    }

    @Test(.enabled(if: Self.hasDevice))
    func aForcedFormatEncodesEveryLevelOnce() throws {
        let converter = try gpu().converter
        let result = try converter.convert(
            gradient(size: 64),
            plan: .forced(.astc6x6),
            path: "a.dds"
        )
        #expect(result.format == .astc6x6)
        #expect(result.width == 64)
    }

    @Test(.enabled(if: Self.hasDevice))
    func aSizeLimitDropsTheTopLevels() throws {
        let converter = try gpu().converter
        let bytes = DDSFixture.file(format: .bc1, width: 64, height: 64, mipCount: 4)
        let converted = try #require(try converter.convert(
            path: "a.dds", bytes: bytes, output: AssetTextureOutput(maximumSide: 16)
        ))
        let ready = try ReadyTextureCodec.decode(converted)
        #expect(ready.width == 16)
        #expect(ready.mipCount == 2)
        #expect(ready.format == .bc1)
    }

    @Test(.enabled(if: Self.hasDevice))
    func theCPUDecodeMatchesTheGPUDecode() throws {
        let gpu = try gpu()
        let source = gradient(size: 64)
        let encoded = try gpu.converter.encode(source, as: .astc6x6)
        let uploaded = try gpu.loader.upload(ready: encoded, usage: .data, label: "astc")
        let viaGPU = try gpu.readback.pixels(of: uploaded, level: 0)
        let viaCPU = try ASTCEncoder.decode(
            encoded.bytes, width: 64, height: 64, block: ASTCBlockSize(width: 6, height: 6)
        )
        let difference = try TextureImageDifference.compare(
            reference: viaGPU,
            candidate: viaCPU,
            normals: false
        )
        #expect(difference.maxChannelError <= 1)
    }

    @Test(.enabled(if: Self.hasDevice), arguments: [
        (ReadyTextureFormat.astc4x4, 40.0), (.astc5x5, 34.0), (.astc6x6, 30.0), (.astc8x8, 30.0)
    ])
    func astcStaysWithinItsLimit(format: ReadyTextureFormat, minimumPSNR: Double) throws {
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
