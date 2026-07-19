// Env-gated preview-pipeline test over the user's own install (read-only
// external input, never committed — AGENTS.md Legal & IP): catalog load (VFS
// enumeration + full record walk), a DDS textured-quad preview and a NIF
// single-model preview through Renderer.renderOffscreen — the exact images
// main-app Asset Browser shows. PNGs land in logs/ for human review. Skips without
// OPENSKY_DATA_ROOT or a Metal 4 GPU (CI has neither game data nor one).

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import opensky
import Testing
import UniformTypeIdentifiers

struct PreviewRealDataTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func browsesAndPreviewsRealAssets() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let vfs = VirtualFileSystem(root: root)
        let loaded = PreviewCatalog.load(
            fileSystem: vfs,
            esmURL: root.dataURL.appending(path: "Skyrim.esm")
        )
        let catalog = loaded.catalog

        // Vanilla SSE: ~172k archive entries, ~870k Skyrim.esm records.
        #expect(catalog.fileCount > 100_000, "archives look under-enumerated")
        #expect(catalog.recordCount > 500_000, "record walk looks truncated")
        #expect(catalog.notes.isEmpty)

        // Tamriel worldspace, FormID 0x3C (UESP "Skyrim Mod:FormIDs").
        let world = try #require(
            catalog.items(for: .records).first { $0.display == "WRLD 0000003C" }
        )
        guard case let .record(record) = world.selection else {
            Issue.record("record row selects a non-record")
            return
        }
        let dump = RecordTextDump.dump(record: record, localized: loaded.localized)
        #expect(dump.contains("WRLD 0000003C"))
        #expect(dump.contains("fields ("))

        try previewTexture(catalog: catalog, vfs: vfs, device: device)
        try previewMesh(catalog: catalog, vfs: vfs, device: device)
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func previewsSkinnedBodyWithoutBindPoseDistortion() throws {
        let root = try #require(Self.dataRoot)
        try previewSkinnedBody(vfs: VirtualFileSystem(root: root))
    }

    /// Milestone 5.3 acceptance: exact Asset Browser preview path over a
    /// vanilla body, plus a CPU bind-pose check against source bounds.
    @MainActor
    private func previewSkinnedBody(vfs: VirtualFileSystem) throws {
        let path = "meshes\\actors\\character\\character assets\\malebody_1.nif"
        let data = try vfs.contents(forPath: path)
        let skeletonData = try vfs.contents(
            forPath: "meshes\\actors\\character\\character assets\\skeleton.nif"
        )
        let skeleton = try NIFSkeleton(file: NIFFile(data: skeletonData))
        let model = try NIFFile(data: data).model(skeleton: skeleton)

        #expect(model.meshes.count == 2)
        #expect(model.meshes.allSatisfy { $0.skinning != nil })
        #expect(model.materials.compactMap(\.diffuseTexture).count == 2)
        let sourceBounds = try #require(ModelBounds.containing(model: model))
        let skinnedBounds = try #require(bindPoseBounds(model: model))
        #expect(simd_distance(sourceBounds.min, skinnedBounds.min) < 0.01)
        #expect(simd_distance(sourceBounds.max, skinnedBounds.max) < 0.01)

        let detail = PreviewDetailBuilder(fileSystem: vfs, localized: false).detail(
            for: .file(VFSEntry(path: path, archive: "Skyrim - Meshes0.bsa"))
        )
        #expect(!detail.text.contains("[ERROR]"))
        #expect(!detail.text.contains("[WARNING] no preview image"))
        let image = try #require(detail.image)
        #expect(nonBackgroundFraction(image: image) > 0.01)
        let url = try write(image: image, name: "preview-skinned-body.png")
        print("[INFO] skinned body preview (\(path)): \(url.path)")
    }

    private func bindPoseBounds(model: Model) -> ModelBounds? {
        var minimum = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var maximum = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var hasVertex = false
        for mesh in model.meshes {
            guard let skinning = mesh.skinning else { continue }
            for index in mesh.positions.indices {
                let position = SIMD4(mesh.positions[index], 1)
                let weights = skinning.weights[index]
                let bones = skinning.boneIndices[index]
                var skinned = SIMD4<Float>.zero
                for lane in 0 ..< 4 where weights[lane] > 0 {
                    skinned += weights[lane] *
                        (skinning.bindPoseMatrices[Int(bones[lane])] * position)
                }
                let point = (mesh.transform * SIMD4(skinned.xyz, 1)).xyz
                minimum = simd_min(minimum, point)
                maximum = simd_max(maximum, point)
                hasVertex = true
            }
        }
        return hasVertex ? ModelBounds(min: minimum, max: maximum) : nil
    }

    /// First architecture DDS whose quad render lights >30% of the frame —
    /// a black texture legitimately fails the pixel check, so keep looking.
    @MainActor
    private func previewTexture(
        catalog: PreviewCatalog,
        vfs: VirtualFileSystem,
        device: MTLDevice
    ) throws {
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let candidates = PreviewCatalog.filter(
            catalog.items(for: .textures),
            query: "textures\\architecture"
        )
        for item in candidates.prefix(50) {
            guard
                case let .file(entry) = item.selection,
                let data = try? vfs.contents(forPath: entry.path),
                let file = try? DDSFile(data: data), file.width >= 128
            else { continue }
            let quad = TexturePreviewScene.model(
                textureKey: entry.path,
                aspect: Float(file.width) / Float(file.height)
            )
            let model = try RenderModel(
                device: device,
                model: quad,
                textureProvider: textures.provider
            )
            let image = try renderImage(
                scene: RenderScene(instances: [RenderPlacement(
                    model: model,
                    transform: matrix_identity_float4x4
                )]),
                camera: TexturePreviewScene.camera(),
                width: 512,
                height: 512,
                device: device
            )
            guard nonBackgroundFraction(image: image) > 0.3 else { continue }
            let url = try write(image: image, name: "preview-dds.png")
            print("[INFO] DDS preview (\(entry.path)): \(url.path)")
            return
        }
        Issue.record("no architecture DDS produced a lit quad preview")
    }

    /// First architecture NIF that loads and draws something.
    @MainActor
    private func previewMesh(
        catalog: PreviewCatalog,
        vfs: VirtualFileSystem,
        device: MTLDevice
    ) throws {
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let candidates = PreviewCatalog.filter(
            catalog.items(for: .meshes),
            query: "meshes\\architecture"
        )
        for item in candidates.prefix(50) {
            guard
                case let .file(entry) = item.selection,
                let model = try? meshes.model(path: entry.path),
                let bounds = meshes.bounds(forPath: entry.path)
            else { continue }
            let image = try renderImage(
                scene: RenderScene(instances: [RenderPlacement(
                    model: model,
                    transform: matrix_identity_float4x4
                )]),
                camera: SceneCamera.framing(bounds: (bounds.min, bounds.max)),
                width: 800,
                height: 600,
                device: device
            )
            guard nonBackgroundFraction(image: image) > 0.01 else { continue }
            let url = try write(image: image, name: "preview-nif.png")
            print("[INFO] NIF preview (\(entry.path)): \(url.path)")
            return
        }
        Issue.record("no architecture NIF produced a lit model preview")
    }

    /// Same wiring the GUI's PreviewDetailBuilder uses.
    @MainActor
    private func renderImage(
        scene: RenderScene,
        camera: SceneCamera,
        width: Int,
        height: Int,
        device: MTLDevice
    ) throws -> CGImage {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: scene, camera: camera)
        let texture = try renderer.renderOffscreen(width: width, height: height)
        return try #require(FrameScreenshot.image(from: texture))
    }

    /// Fraction of pixels above the black clear color's noise floor.
    private func nonBackgroundFraction(image: CGImage) -> Double {
        guard let data = image.dataProvider?.data as Data? else { return 0 }
        var lit = 0
        let pixelCount = data.count / 4
        for pixel in stride(from: 0, to: pixelCount * 4, by: 4) {
            if data[pixel] > 8 || data[pixel + 1] > 8 || data[pixel + 2] > 8 {
                lit += 1
            }
        }
        return Double(lit) / Double(max(pixelCount, 1))
    }

    /// Repo root derived from this source file's location; logs/ is the
    /// designated gitignored output directory (AGENTS.md "Code scripts").
    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }

    private func write(image: CGImage, name: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        let url = logsDirectory.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}
