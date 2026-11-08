// The parallel texture prefetch must load what the serial path loads, with the same
// counters. Synthetic loose DDS files only (AGENTS.md Legal).

import Foundation
import Metal
import OpenSkyFormatsCore
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyRenderResources
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.gpu), .unlessPlanSkips(.gpu))
struct TextureLibraryPrefetchTests {
    private static let device = MTLCreateSystemDefaultDevice()

    private static var hasDevice: Bool {
        device != nil
    }

    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-prefetch-\(UUID().uuidString)", directoryHint: .isDirectory)
        for name in ["a", "b", "c", "d", "e"] {
            let url = dataURL.appending(path: "textures/\(name).dds")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try DDSFixture.file(format: .rgba8888, width: 4, height: 4, mipCount: 1).write(to: url)
        }
    }

    private func library(parallel: Bool) throws -> TextureLibrary {
        let device = try #require(Self.device)
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let library = try TextureLibrary(fileSystem: vfs, device: device)
        library.decodesInParallel = parallel
        return library
    }

    private static let materials = ["a", "b", "c", "d", "e"].map { name in
        Material(
            diffuseTexture: "textures\\\(name).dds",
            normalTexture: name == "a" ? "textures\\missing_n.dds" : "textures\\\(name).dds",
            uvOffset: .zero, uvScale: SIMD2(1, 1), alpha: 1, glossiness: 80,
            specularColor: SIMD3(1, 1, 1), specularStrength: 1, doubleSided: false,
            alphaBlend: false, alphaTestThreshold: nil
        )
    }

    private func load(_ library: TextureLibrary) -> [any MTLTexture] {
        library.prefetch(materials: Self.materials)
        return Self.materials.flatMap { material in
            [
                library.texture(key: material.diffuseTexture, usage: .color),
                library.texture(key: material.normalTexture, usage: .data)
            ]
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func prefetchLoadsWhatTheSerialPathLoads() throws {
        let parallel = try library(parallel: true)
        parallel.prefetch(materials: Self.materials)
        #expect(parallel.prefetched.count == 10)
        #expect(parallel.prefetched.values.filter { $0.uploaded != nil }.count == 9)
        let serial = try library(parallel: false)
        let fromPrefetch = load(parallel)
        let fromSerial = load(serial)
        #expect(fromPrefetch.map(\.pixelFormat) == fromSerial.map(\.pixelFormat))
        #expect(fromPrefetch.map(\.width) == fromSerial.map(\.width))
        #expect(fromPrefetch.map(\.label) == fromSerial.map(\.label))
        #expect(parallel.loadedCount == serial.loadedCount)
        #expect(parallel.missingPaths == ["textures\\missing_n.dds"])
        #expect(parallel.missingPaths == serial.missingPaths)
        #expect(parallel.prefetched.isEmpty)
    }

    @Test(.enabled(if: Self.hasDevice)) func prefetchSkipsLoadedTexturesAndCanBeOff() throws {
        let parallel = try library(parallel: true)
        _ = load(parallel)
        parallel.prefetch(materials: Self.materials)
        #expect(parallel.prefetched.isEmpty)
        let serial = try library(parallel: false)
        serial.prefetch(materials: Self.materials)
        #expect(serial.prefetched.isEmpty)
    }
}
