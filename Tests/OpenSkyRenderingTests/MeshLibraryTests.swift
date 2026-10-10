// MeshLibrary cache/normalization/error tests over a synthetic VFS (temp-dir
// loose files) + NIFFixture bytes. Needs a Metal device (buffer upload, no
// BCn — untextured fallback material). Fixtures are built in code — never
// extracted game files (AGENTS.md Legal & IP boundary).

import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsTesting
@testable import OpenSkyGameData
@testable import OpenSkyRendering
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.gpu))
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

    private func library(device: MTLDevice) throws -> MeshLibrary {
        let vfs = VirtualFileSystem(dataURL: dataURL, archiveURLs: [])
        let textures = try TextureLibrary(fileSystem: vfs, device: device)
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

    /// A fire emitter, with a drawable shape like a campfire static or without one.
    private func fireNIF(withShape: Bool = true) -> Data {
        let emitter = NIFParticleFixture.boxEmitter(
            base: NIFParticleFixture.modifierBase(),
            emitter: NIFParticleFixture.emitterBase(),
            width: 10, height: 10, depth: 10
        )
        let system = NIFParticleFixture.particleSystemSSE(
            shaderPropertyRef: 4, dataRef: 2, modifierRefs: [3]
        )
        let shader = NIFParticleFixture.effectShaderProperty(sourceTexture: "textures/fire.dds")
        let blocks: [NIFFixture.Block] = [
            .init("NiNode", NIFFixture.niNode(children: withShape ? [1, 5] : [1])),
            .init("NiParticleSystem", system),
            .init("NiPSysData", NIFParticleFixture.psysData(maxParticles: 16)),
            .init("NiPSysBoxEmitter", emitter),
            .init("BSEffectShaderProperty", shader)
        ]
        return NIFFixture.file(blocks: blocks + (withShape ? [.init("BSTriShape", shape())] : []))
    }

    @Test(.enabled(if: Self.hasDevice)) func aRetexturedModelKeepsItsParticles() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/fx/campfire.nif", fireNIF())
        let library = try library(device: device)
        let surface = ModelSurfaceOverride(
            diffuseTexture: nil, normalTexture: nil, tint: nil,
            shapes: [.init(
                shapeName: "Logs",
                diffuseTexture: "textures/ash.dds",
                normalTexture: nil
            )]
        )
        _ = try library.model(path: "meshes\\fx\\campfire.nif", surface: surface)
        let playbacks = try library.particlePlaybacks(
            path: "meshes\\fx\\campfire.nif", surface: surface,
            placementTransform: matrix_identity_float4x4, formID: 1
        )
        #expect(playbacks.count == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func aParticleOnlyModelKeepsItsParticles() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/fx/flames.nif", fireNIF(withShape: false))
        let library = try library(device: device)
        let model = try library.model(path: "meshes\\fx\\flames.nif")
        let playbacks = try library.particlePlaybacks(
            path: "meshes\\fx\\flames.nif", placementTransform: matrix_identity_float4x4, formID: 1
        )
        #expect(model.meshes.isEmpty)
        #expect(playbacks.count == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func cachesModelByKey() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/clutter/cup.nif", staticNIF())
        let library = try library(device: device)
        let first = try library.model(path: "meshes\\clutter\\cup.nif")
        let second = try library.model(path: "meshes\\clutter\\cup.nif")
        #expect(first === second) // shared instance across refs
        #expect(library.loadedCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func prependsMeshesPrefixWhenOmitted() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/clutter/cup.nif", staticNIF())
        let library = try library(device: device)
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
        let library = try library(device: device)
        let canonical = try library.model(path: "meshes\\clutter\\cup.nif")
        let variant = try library.model(path: "Meshes/Clutter\\CUP.NIF")
        #expect(canonical === variant)
        #expect(library.loadedCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func missingFileThrowsNotFound() throws {
        let device = try #require(Self.device)
        let library = try library(device: device)
        #expect(throws: MeshLibraryError.fileNotFound(path: "meshes\\clutter\\absent.nif")) {
            _ = try library.model(path: "clutter\\absent.nif")
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func malformedNIFThrowsParseFailed() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/bad.nif", Data("not a nif file".utf8))
        let library = try library(device: device)
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
        let library = try library(device: device)
        #expect(throws: MeshLibraryError.emptyModel(path: "meshes\\empty.nif")) {
            _ = try library.model(path: "empty.nif")
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func markerOnlyModelThrowsEditorMarkerOnly() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/marker.nif", NIFFixture.file(
            blocks: [
                .init("NiNode", NIFFixture.niNode(children: [1])),
                .init("BSTriShape", NIFFixture.bsTriShape(
                    prefix: NIFFixture.avObjectPrefix(nameIndex: 0),
                    attributes: Self.staticAttributes,
                    strideDwords: Self.staticStrideDwords
                ))
            ],
            strings: ["EditorMarker"]
        ))
        let library = try library(device: device)
        #expect(throws: MeshLibraryError.editorMarkerOnly(path: "meshes\\marker.nif")) {
            _ = try library.model(path: "marker.nif")
        }
    }

    @Test(.enabled(if: Self.hasDevice)) func reportsSkippedShapeCount() throws {
        let device = try #require(Self.device)
        // One empty shape (dropped) + one drawable shape (kept).
        try writeLooseFile("meshes/mixed.nif", NIFFixture.file(blocks: [
            .init("NiNode", NIFFixture.niNode(children: [1, 2])),
            .init("BSTriShape", NIFFixture.bsTriShape(
                attributes: Self.staticAttributes,
                strideDwords: Self.staticStrideDwords
            )),
            .init("BSTriShape", shape())
        ]))
        let library = try library(device: device)
        _ = try library.model(path: "mixed.nif")
        #expect(library.skippedShapeCount(forPath: "mixed.nif") == 1)
        #expect(library.totalSkippedShapeCount == 1)
    }

    @Test(.enabled(if: Self.hasDevice)) func recordsModelBoundsAtLoad() throws {
        let device = try #require(Self.device)
        try writeLooseFile("meshes/clutter/cup.nif", staticNIF())
        let library = try library(device: device)
        #expect(library.bounds(forPath: "clutter\\cup.nif") == nil) // not loaded yet
        _ = try library.model(path: "clutter\\cup.nif")
        // shape() places all three vertices at (1, 2, 3) -> point bounds.
        #expect(library.bounds(forPath: "clutter\\cup.nif")
            == ModelBounds(min: SIMD3(1, 2, 3), max: SIMD3(1, 2, 3)))
    }

    @Test(.enabled(if: Self.hasDevice)) func invalidPathThrowsNotFound() throws {
        let device = try #require(Self.device)
        let library = try library(device: device)
        #expect(throws: MeshLibraryError.self) {
            _ = try library.model(path: "")
        }
    }
}
