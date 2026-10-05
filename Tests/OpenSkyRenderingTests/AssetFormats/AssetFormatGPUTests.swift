// Cache payloads on the GPU: ASTC encoding, the readback decoder, and loading
// through the CPU path and MTLIO, over synthetic images.

import FormatsMeshTesting
import Foundation
import Metal
@testable import OpenSkyFormatsMesh
@testable import OpenSkyRendering
import RenderingTesting
import TagsTesting
import Testing

@Suite(.tags(.gpu))
@MainActor
struct AssetFormatGPUTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private func device() throws -> MTLDevice {
        try #require(Self.device, "no Metal device")
    }

    private func readback() throws -> TextureReadback {
        let device = try device()
        return try TextureReadback(
            device: device,
            library: ShaderLibraryFixture.library(device: device)
        )
    }

    /// A smooth gradient: red grows left to right, green top to bottom.
    private static func gradient(width: Int, height: Int) -> TexturePixels {
        var rgba: [UInt8] = []
        for row in 0 ..< height {
            for column in 0 ..< width {
                rgba += [
                    UInt8(column * 255 / max(1, width - 1)),
                    UInt8(row * 255 / max(1, height - 1)),
                    96, 255
                ]
            }
        }
        return TexturePixels(width: width, height: height, rgba: rgba)
    }

    @Test func rgba8PayloadReadsBackExactly() throws {
        let image = Self.gradient(width: 7, height: 5)
        let payload = try GPUTexturePayload.rgba8(levels: [image])
        let texture = try payload.upload(device: device(), source: payload.bytes)
        #expect(try readback().pixels(of: texture, level: 0) == image)
    }

    @Test(arguments: ASTCBlockSize.square)
    func astcKeepsOrientationAndCloseColors(block: ASTCBlockSize) throws {
        let image = Self.gradient(width: 64, height: 48)
        let payload = try GPUTexturePayload.astc(levels: [image], block: block, effort: .medium)
        let texture = try payload.upload(device: device(), source: payload.bytes)
        let decoded = try readback().pixels(of: texture, level: 0)
        let difference = try TextureImageDifference.compare(
            reference: image, candidate: decoded, normals: false
        )
        // A flipped image would put green 255 where 0 belongs: far below 30 dB.
        #expect(difference.rgbPSNR > 30)
    }

    @Test func shippedPayloadKeepsTheDDSLevels() throws {
        let level0 = Data((0 ..< 64).map { UInt8($0) })
        let level1 = Data((0 ..< 16).map { UInt8(200 + $0) })
        let dds = try DDSFile(
            data: DDSFixture.rgba8888File(
                width: 4,
                height: 4,
                mipCount: 2,
                payload: level0 + level1
            )
        )
        let half = try GPUTexturePayload.shipped(dds, droppedLevels: 1)
        #expect(half.levels.count == 1)
        #expect(half.width == 2)
        #expect(half.bytes == level1)
        let texture = try half.upload(device: device(), source: half.bytes)
        let scaled = try readback().pixels(of: texture, width: 4, height: 4)
        #expect(scaled.width == 4)
        #expect(scaled.rgba.count == 64)
    }

    @Test(arguments: AssetFileStorage.allCases)
    func cacheFilesLoadBackOnBothPaths(storage: AssetFileStorage) throws {
        let device = try device()
        let payload = try GPUTexturePayload.rgba8(levels: [
            Self.gradient(width: 32, height: 16), Self.gradient(width: 16, height: 8)
        ])
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-asset-\(UUID().uuidString).\(storage.rawValue)")
        defer { try? FileManager.default.removeItem(at: url) }
        try AssetFileLoader.write(payload.bytes, to: url, storage: storage)
        let loader = try AssetFileLoader(device: device)

        #expect(try loader.read(url, storage: storage, byteCount: payload.bytes.count) == payload
            .bytes)

        let texture = try payload.makeEmptyTexture(device: device)
        try loader.load(url, storage: storage, layout: payload, into: texture)
        let level = payload.levels[1]
        var loaded = [UInt8](repeating: 0, count: level.length)
        texture.getBytes(
            &loaded, bytesPerRow: level.bytesPerRow,
            from: MTLRegionMake2D(0, 0, level.width, level.height), mipmapLevel: 1
        )
        #expect(Data(loaded) == payload.bytes
            .subdata(in: level.offset ..< level.offset + level.length))

        let buffer = try #require(device.makeBuffer(length: 8, options: .storageModeShared))
        try loader.load(url, storage: storage, ranges: [(buffer, 4)])
        #expect(Data(bytes: buffer.contents(), count: 8) == payload.bytes.subdata(in: 4 ..< 12))
    }
}
