// Volume textures through the loader, the library, and an effect material, over
// synthetic L8 volumes built in code (DDSFixture). No game files.

import Foundation
import Metal
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyRenderResources
import OpenSkyShaderTypes
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct TextureVolumeTests {
    private static let device = MTLCreateSystemDefaultDevice()
    private static var hasDevice: Bool {
        device != nil
    }

    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-volume-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    /// An L8 volume whose texels each hold their level and slice: `level * 16 + slice + 1`.
    private static func volume(size: Int, mipCount: Int, cut: Int = 0) -> Data {
        var payload = Data()
        for level in 0 ..< mipCount {
            let edge = max(1, size >> level)
            for slice in 0 ..< edge {
                payload.append(Data(repeating: UInt8(level * 16 + slice + 1), count: edge * edge))
            }
        }
        return DDSFixture.file(
            width: UInt32(size), height: UInt32(size), depth: UInt32(size),
            mipCount: UInt32(mipCount), pixelFlags: 0x20000, fourCC: "\0\0\0\0",
            rgbBitCount: 8, redMask: 0xFF, caps2: 0x200000, payload: payload.dropLast(cut)
        )
    }

    private static func flat2D() -> Data {
        DDSFixture.file(
            width: 1, height: 1, pixelFlags: 0x40, fourCC: "\0\0\0\0", rgbBitCount: 32,
            redMask: 0x00FF_0000, greenMask: 0x0000_FF00, blueMask: 0x0000_00FF,
            payload: Data([10, 20, 30, 0])
        )
    }

    private func library(_ device: MTLDevice, files: [String: Data]) throws -> TextureLibrary {
        for (path, data) in files {
            let url = dataURL.appending(path: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url)
        }
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        return try TextureLibrary(fileSystem: vfs, device: device)
    }

    @Test(.enabled(if: Self.hasDevice)) func uploadsEveryLevelAndSliceOfAVolume() throws {
        let loader = try TextureLoader(device: #require(Self.device))
        let texture = loader.texture(
            dds: Self.volume(size: 4, mipCount: 3),
            usage: .volume,
            label: "v"
        )
        #expect(texture.textureType == .type3D)
        #expect((texture.width, texture.height, texture.depth) == (4, 4, 4))
        #expect(texture.mipmapLevelCount == 3)
        let top = try TextureReadback.volumeSlices(of: texture, level: 0)
        #expect(top.count == 4)
        #expect(top.map { Array($0.rgba.prefix(4)) } == (1 ... 4).map { [$0, $0, $0, 255] })
        let middle = try TextureReadback.volumeSlices(of: texture, level: 1)
        #expect(middle.map { $0.rgba[0] } == [17, 18])
    }

    @Test(.enabled(if: Self.hasDevice)) func aBrokenVolumeGetsTheNeutralVolumePlaceholder() throws {
        let loader = try TextureLoader(device: #require(Self.device))
        let broken = Self.volume(size: 4, mipCount: 3, cut: 1)
        #expect(DDSFile.declaresVolume(broken))
        let texture = loader.texture(dds: broken, usage: .volume, label: "broken")
        #expect(texture.textureType == .type3D)
        #expect(texture.label == "placeholder-volume")
        let slice = try TextureReadback.volumeSlices(of: texture, level: 0)
        #expect(slice.map(\.rgba) == [[128, 128, 128, 255]])
    }

    @Test(.enabled(if: Self.hasDevice)) func anEffectSourceVolumeBindsAs3DOnly() throws {
        let device = try #require(Self.device)
        let library = try library(device, files: [
            "textures/effects/noise.dds": Self.volume(size: 4, mipCount: 3),
            "textures/effects/flat.dds": Self.flat2D()
        ])
        let colour = library.texture(key: "textures\\effects\\noise.dds", usage: .color)
        #expect(colour.textureType == .type2D)
        #expect(colour.label == "placeholder-color")
        let source = library.texture(key: "textures\\effects\\noise.dds", usage: .effectSource)
        #expect(source.textureType == .type3D)
        #expect(source.mipmapLevelCount == 3)
        #expect(library.volumePaths == ["textures\\effects\\noise.dds"])
        let flat = library.texture(key: "textures\\effects\\flat.dds", usage: .effectSource)
        #expect(flat === library.texture(key: "textures\\effects\\flat.dds", usage: .color))
    }

    @Test(.enabled(if: Self.hasDevice)) func anEffectMaterialFlagsItsVolumeSource() throws {
        let device = try #require(Self.device)
        let library = try library(device, files: [
            "textures/effects/noise.dds": Self.volume(size: 2, mipCount: 1),
            "textures/effects/flat.dds": Self.flat2D()
        ])
        let shading = EffectShading(
            baseColor: SIMD4(repeating: 1), baseColorScale: 1, paletteTexture: nil,
            paletteColor: false, paletteAlpha: false, falloff: nil, vertexColors: false,
            vertexAlpha: false
        )
        let flag = UInt32(EffectFlag.sourceVolume.rawValue)
        let volume = RenderEffectMaterial(
            shading: shading, source: "textures\\effects\\noise.dds",
            textureProvider: library.provider
        )
        #expect(volume.sourceVolume?.textureType == .type3D)
        #expect(volume.flags & flag != 0)
        let flat = RenderEffectMaterial(
            shading: shading, source: "textures\\effects\\flat.dds",
            textureProvider: library.provider
        )
        #expect(flat.sourceVolume == nil)
        #expect(flat.flags & flag == 0)
    }
}
