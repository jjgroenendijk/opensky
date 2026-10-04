// Builds the detail pane for one selection: decoded info text plus (NIF/DDS)
// an offscreen-rendered preview image through the same engine path the game
// renderer uses. Files are read and parsed off the main actor; only the render
// runs on it. Failures become [ERROR] text. Pipeline: docs/tools/preview-gui.md.

import AppKit
import Metal
import MetalKit
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPreview
import OpenSkyRendering
import OpenSkyWorld
import simd
import Synchronization

/// The selection's text, and the scene to render when the file has a picture.
nonisolated struct PreviewDetailDraft: Sendable {
    let text: String
    let render: PreviewRender?

    init(text: String, render: PreviewRender? = nil) {
        self.text = text
        self.render = render
    }
}

nonisolated struct PreviewRender: Sendable {
    let device: any MTLDevice
    let scene: RenderScene
    let camera: SceneCamera
    let width: Int
    let height: Int
}

/// The main-actor side: drafts each selection on the concurrent pool, then renders.
final class PreviewDetailLoader {
    struct Detail {
        let text: String
        let image: CGImage?
    }

    private let worker: PreviewDetailWorker

    init(fileSystem: any GameFileSource, referenceInspector: ReferenceRecordInspector? = nil) {
        worker = PreviewDetailWorker(
            builder: PreviewDetailBuilder(
                fileSystem: fileSystem,
                referenceInspector: referenceInspector
            )
        )
    }

    func detail(for selection: PreviewSelection) async -> Detail {
        let draft = await worker.draft(for: selection)
        return Detail(text: draft.text, image: draft.render.flatMap(Self.image))
    }

    /// Headless MTKView carries the pixel-format config Renderer reads;
    /// renderOffscreen never touches its drawable (CLI render pattern).
    private static func image(_ render: PreviewRender) -> CGImage? {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: render.width, height: render.height),
            device: render.device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        guard
            let renderer = try? Renderer(view: view, scene: render.scene, camera: render.camera),
            let texture = try? renderer.renderOffscreen(width: render.width, height: render.height)
        else { return nil }
        return FrameScreenshot.image(from: texture)
    }
}

/// Owns the builder and its mesh and texture caches; one draft at a time.
nonisolated final class PreviewDetailWorker: Sendable {
    private let builder: Mutex<PreviewDetailBuilder>

    init(builder: sending PreviewDetailBuilder) {
        self.builder = Mutex(builder)
    }

    @concurrent
    func draft(for selection: PreviewSelection) async -> PreviewDetailDraft {
        builder.withLock { $0.draft(for: selection) }
    }
}

nonisolated final class PreviewDetailBuilder {
    typealias Detail = PreviewDetailDraft

    let fileSystem: any GameFileSource
    private let referenceInspector: ReferenceRecordInspector?
    /// Nil without a Metal 4 GPU or its texture placeholders; previews are then text-only.
    private let device: (any MTLDevice)?
    private let textures: TextureLibrary?
    private let meshes: MeshLibrary?

    init(
        fileSystem: any GameFileSource,
        referenceInspector: ReferenceRecordInspector? = nil
    ) {
        self.fileSystem = fileSystem
        self.referenceInspector = referenceInspector
        if
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4),
            let textures = try? TextureLibrary(fileSystem: fileSystem, device: device)
        {
            self.device = device
            self.textures = textures
            meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        } else {
            device = nil
            textures = nil
            meshes = nil
        }
    }

    func draft(for selection: PreviewSelection) -> Detail {
        switch selection {
        case let .record(record):
            Detail(text: recordText(record))
        case let .file(entry):
            fileDetail(entry: entry)
        }
    }

    private func recordText(_ preview: PreviewRecord) -> String {
        let text = referenceInspector?.text(for: preview)
            ?? RecordTextDump.dump(record: preview.record, localized: preview.localized)
        return bodyPartNodes(preview).map { text + "\n\n" + $0 } ?? text
    }

    // MARK: - Files

    private func fileDetail(entry: VFSEntry) -> Detail {
        let data: Data
        do {
            data = try fileSystem.contents(forPath: entry.path)
        } catch {
            return Detail(
                text: "[ERROR] cannot read \(entry.path): \(String(describing: error))"
            )
        }
        let header = "\(entry.path)\narchive: \(entry.archive)\n\(data.count) bytes\n\n"
        if entry.path.hasSuffix(".nif") {
            return nifDetail(header: header, path: entry.path, data: data)
        }
        if entry.path.hasSuffix(".dds") {
            return ddsDetail(header: header, path: entry.path, data: data)
        }
        if entry.path.hasSuffix(".hkt") {
            return Detail(text: header + tagfileText(data))
        }
        return Detail(text: header + "(no preview for this file type)")
    }

    private func nifDetail(header: String, path: String, data: Data) -> Detail {
        let file: NIFFile
        do {
            file = try NIFFile(data: data)
        } catch {
            return Detail(
                text: header + "[ERROR] NIF parse failed: \(String(describing: error))"
            )
        }
        let text = header + AssetInfoText.nif(file: file)
        guard let meshes else {
            return Detail(text: text + Self.noGPUNote)
        }
        let model: RenderModel
        do {
            model = try meshes.model(path: path)
        } catch {
            let reason = String(describing: error)
            return Detail(
                text: text + "\n[WARNING] no preview image: \(reason)"
            )
        }
        guard let bounds = meshes.bounds(forPath: path) else {
            return Detail(text: text + "\n[WARNING] no bounds — nothing to frame")
        }
        let scene = RenderScene(instances: [
            RenderPlacement(model: model, transform: matrix_identity_float4x4)
        ])
        let camera = SceneCamera.framing(bounds: (bounds.min, bounds.max))
        return Detail(
            text: text,
            render: render(scene: scene, camera: camera, width: 1024, height: 768)
        )
    }

    private func ddsDetail(header: String, path: String, data: Data) -> Detail {
        let file: DDSFile
        do {
            file = try DDSFile(data: data)
        } catch {
            return Detail(
                text: header + "[ERROR] DDS parse failed: \(String(describing: error))"
            )
        }
        let text = header + AssetInfoText.dds(file: file, byteCount: data.count)
        guard let device, let textures else {
            return Detail(text: text + Self.noGPUNote)
        }
        let aspect = Float(file.width) / Float(file.height)
        let quad = TexturePreviewScene.model(textureKey: path, aspect: aspect)
        guard
            let model = try? RenderModel(
                device: device,
                model: quad,
                textureProvider: textures.provider
            )
        else {
            return Detail(
                text: text + "\n[WARNING] no preview image: GPU transfer failed"
            )
        }
        let scene = RenderScene(instances: [
            RenderPlacement(model: model, transform: matrix_identity_float4x4)
        ])
        let size = Self.imageSize(width: file.width, height: file.height)
        return Detail(
            text: text,
            render: render(
                scene: scene,
                camera: TexturePreviewScene.camera(),
                width: size.width,
                height: size.height
            )
        )
    }

    private static let noGPUNote = "\n[INFO] no Metal 4 GPU — preview image unavailable"

    /// Output size: texture-native, capped to 1024 on the long edge (the
    /// image view scales small textures up for display).
    static func imageSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = min(1.0, 1024.0 / Double(max(width, height, 1)))
        return (
            max(1, Int(Double(width) * scale)),
            max(1, Int(Double(height) * scale))
        )
    }

    private func render(
        scene: RenderScene,
        camera: SceneCamera,
        width: Int,
        height: Int
    ) -> PreviewRender? {
        device.map {
            PreviewRender(device: $0, scene: scene, camera: camera, width: width, height: height)
        }
    }
}
