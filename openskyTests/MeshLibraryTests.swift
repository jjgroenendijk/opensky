// MeshLibrary cache/normalization/error tests over a synthetic VFS (temp-dir
// loose files) + NIFFixture bytes. Needs a Metal device (buffer upload, no
// BCn — untextured fallback material). Fixtures are built in code — never
// extracted game files (AGENTS.md Legal & IP boundary).

import Foundation
import Metal
@testable import opensky
import Testing

struct MeshLibraryTests {
    private static let device = MTLCreateSystemDefaultDevice()
    private static var hasDevice: Bool {
        device != nil
    }

    private static let staticAttributes: UInt16 = 0x1B
    private static let staticStrideDwords = 7

    private let dataURL: URL

    init() throws {
        dataURL = FileManager.default.temporaryDirectory
            .appending(path: "opensky-meshlib-\(UUID().uuidString)", directoryHint: .isDirectory)
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

    private func library(device: MTLDevice) -> MeshLibrary {
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        return MeshLibrary(fileSystem: vfs, device: device, textures: textures)
    }

    /// One static one-triangle BSTriShape payload (SSE interleaved record).
    private func shape(skinRef: Int32 = -1) -> Data {
        var record = Data()
        record.appendFloat32(1)
        record.appendFloat32(2)
        record.appendFloat32(3)
        record.appendFloat32(0) // bitangent X
        record.appendFloat16(0)
        record.appendFloat16(0)
        record.append(contentsOf: [128, 128, 255, 128]) // normal + bitangent Y
        record.append(contentsOf: [255, 128, 128, 128]) // tangent + bitangent Z
        return NIFFixture.bsTriShape(
            skinRef: skinRef,
            attributes: Self.staticAttributes,
            strideDwords: Self.staticStrideDwords,
            vertexRecords: Array(repeating: record, count: 3),
            triangles: [0, 1, 2]
        )
    }

    /// Well-formed static NIF: one drawable shape under a root node.
    private func staticNIF() -> Data {
        NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1])),
            .init("BSTriShape", shape())
        ])
    }

    @Test(.enabled(if: Self.hasDevice)) func cachesModelByKey() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/clutter/cup.nif", staticNIF())
        let library = library(device: device)
        let first = try library.model(path: "meshes\\clutter\\cup.nif")
        let second = try library.model(path: "meshes\\clutter\\cup.nif")
        #expect(first === second) // shared instance across refs
        #expect(library.loadedCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func prependsMeshesPrefixWhenOmitted() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/clutter/cup.nif", staticNIF())
        let library = library(device: device)
        // Record-style path without the "meshes\\" root resolves + shares the
        // same instance as the fully qualified one.
        let bare = try library.model(path: "clutter\\cup.nif")
        let full = try library.model(path: "meshes\\clutter\\cup.nif")
        #expect(bare === full)
        #expect(library.loadedCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func normalizationVariantsHitOneEntry() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/clutter/cup.nif", staticNIF())
        let library = library(device: device)
        let canonical = try library.model(path: "meshes\\clutter\\cup.nif")
        let variant = try library.model(path: "Meshes/Clutter\\CUP.NIF")
        #expect(canonical === variant)
        #expect(library.loadedCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func missingFileThrowsNotFound() throws {
        let device = try #require(Self.device)
        let library = library(device: device)
        #expect(throws: MeshLibraryError.fileNotFound(path: "meshes\\clutter\\absent.nif")) {
            _ = try library.model(path: "clutter\\absent.nif")
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func malformedNIFThrowsParseFailed() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/bad.nif", Data("not a nif file".utf8))
        let library = library(device: device)
        #expect(throws: MeshLibraryError.self) {
            _ = try library.model(path: "bad.nif")
        }
        #expect(library.loadedCount == 0)
    }

    @Test(.enabled(if: Self.hasDevice)) func emptyModelThrows() throws {
        let device = try #require(Self.device)
        // Root -1 -> zero drawable meshes: valid NIF, nothing to place.
        try writeLooseFile("meshes/empty.nif", NIFFixture.file(
            blocks: [.init("NiNode", NIFFixture.niNode())],
            roots: [-1]
        ))
        let library = library(device: device)
        #expect(throws: MeshLibraryError.emptyModel(path: "meshes\\empty.nif")) {
            _ = try library.model(path: "empty.nif")
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func reportsSkippedShapeCount() throws {
        let device = try #require(Self.device)
        // One skinned shape (dropped) + one static shape (kept).
        try writeLooseFile("meshes/mixed.nif", NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("BSTriShape", shape(skinRef: 3)),
            .init("BSTriShape", shape())
        ]))
        let library = library(device: device)
        _ = try library.model(path: "mixed.nif")
        #expect(library.skippedShapeCount(forPath: "mixed.nif") == 1)
        #expect(library.totalSkippedShapeCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func invalidPathThrowsNotFound() throws {
        let device = try #require(Self.device)
        let library = library(device: device)
        #expect(throws: MeshLibraryError.self) {
            _ = try library.model(path: "")
        }
    }
}
