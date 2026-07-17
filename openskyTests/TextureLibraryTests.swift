// TextureLibrary cache/counter tests over a synthetic VFS (temp-dir loose
// files) + DDSFixture bytes. Placeholder-path tests use plain formats and run
// anywhere; the one real upload gates on BCn like TextureLoaderTests.
// Fixtures are built in code — never extracted game files (AGENTS.md Legal).

import Foundation
import Metal
@testable import opensky
import Testing

struct TextureLibraryTests {
    /// nil when this machine cannot run BCn upload tests.
    private static let bcDevice: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsBCTextureCompression else { return nil }
        return device
    }()

    private static var hasBCDevice: Bool {
        bcDevice != nil
    }

    /// Any Metal device — placeholder paths never touch BCn.
    private static let anyDevice = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        anyDevice != nil
    }

    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-texlib-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dataURL, withIntermediateDirectories: true)
    }

    private func writeLooseFile(_ relativePath: String, _ contents: Data) throws {
        let url = dataURL.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url)
    }

    private func library(device: MTLDevice) -> TextureLibrary {
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        return TextureLibrary(fileSystem: vfs, device: device)
    }

    @Test(.enabled(if: Self.hasDevice)) func nilKeyReturnsSharedPlaceholderUncounted() throws {
        let device = try #require(Self.anyDevice)
        let library = library(device: device)
        let first = library.texture(key: nil, usage: .color)
        let second = library.texture(key: nil, usage: .color)
        #expect(first === second)
        #expect(library.loadedCount == 0)
        #expect(library.missingCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func missingPathPlaceholderIdentityAndCounter() throws {
        let device = try #require(Self.anyDevice)
        let library = library(device: device)
        let first = library.texture(key: "textures\\nope.dds", usage: .color)
        let second = library.texture(key: "textures\\nope.dds", usage: .color)
        #expect(first === second)
        // Second lookup of the same path is a cache hit — counted once.
        #expect(library.missingCount == 1)
        _ = library.texture(key: "textures\\other.dds", usage: .color)
        #expect(library.missingCount == 2)
    }

    @Test(.enabled(if: Self.hasDevice)) func normalizationVariantsHitOneEntry() throws {
        let device = try #require(Self.anyDevice)
        let library = library(device: device)
        let canonical = library.texture(key: "textures\\sky\\night.dds", usage: .color)
        let variant = library.texture(key: "Textures/Sky\\NIGHT.DDS", usage: .color)
        #expect(canonical === variant)
        #expect(library.missingCount == 1) // one cache entry, one miss
    }

    @Test(.enabled(if: Self.hasDevice)) func colorAndDataUsageAreDistinctEntries() throws {
        let device = try #require(Self.anyDevice)
        let library = library(device: device)
        let color = library.texture(key: "textures\\a.dds", usage: .color)
        let data = library.texture(key: "textures\\a.dds", usage: .data)
        #expect(color !== data)
        #expect(color.pixelFormat == .rgba8Unorm_srgb)
        #expect(data.pixelFormat == .rgba8Unorm)
        #expect(library.missingCount == 2)
    }

    @Test(.enabled(if: Self.hasDevice)) func providerMatchesTextureMethod() throws {
        let device = try #require(Self.anyDevice)
        let library = library(device: device)
        let direct = library.texture(key: "textures\\a.dds", usage: .color)
        let viaProvider = library.provider("textures\\a.dds", .color)
        #expect(direct === viaProvider)
    }

    @Test(.enabled(if: Self.hasBCDevice)) func loadsAndCachesRealTexture() throws {
        let device = try #require(Self.bcDevice)
        try writeLooseFile("textures/rock.dds", DDSFixture.file(
            format: .bc7,
            width: 8,
            height: 8,
            mipCount: 1
        ))
        let library = library(device: device)
        let first = library.texture(key: "textures\\rock.dds", usage: .color)
        let second = library.texture(key: "Textures/Rock.DDS", usage: .color)
        #expect(first === second) // shared instance across refs
        #expect(first.width == 8)
        #expect(first.pixelFormat == .bc7_rgbaUnorm_srgb)
        #expect(library.loadedCount == 1)
        #expect(library.missingCount == 0)
    }
}
