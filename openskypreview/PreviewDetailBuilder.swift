// Builds the detail pane for one selection: decoded info text plus (NIF/DDS)
// an offscreen-rendered preview image through the same engine path the game
// renderer uses. MeshLibrary/TextureLibrary caches stay warm across
// selections. Failures never crash the browser — they become [ERROR] text
// (AGENTS.md mod-quirk rule). Pipeline: docs/tools/preview-gui.md.

import AppKit
import Metal
import MetalKit
import simd

final class PreviewDetailBuilder {
    struct Detail {
        let text: String
        let image: CGImage?
    }

    private let fileSystem: VirtualFileSystem
    private let localized: Bool
    /// Nil when the machine lacks a Metal 4 GPU — text-only previews then.
    private let device: (any MTLDevice)?
    private let textures: TextureLibrary?
    private let meshes: MeshLibrary?

    init(fileSystem: VirtualFileSystem, localized: Bool) {
        self.fileSystem = fileSystem
        self.localized = localized
        if let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4) {
            self.device = device
            let textures = TextureLibrary(fileSystem: fileSystem, device: device)
            self.textures = textures
            meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        } else {
            device = nil
            textures = nil
            meshes = nil
        }
    }

    func detail(for selection: PreviewSelection) -> Detail {
        switch selection {
        case let .record(record):
            Detail(text: RecordTextDump.dump(record: record, localized: localized), image: nil)
        case let .file(entry):
            fileDetail(entry: entry)
        }
    }

    // MARK: - Files

    private func fileDetail(entry: VFSEntry) -> Detail {
        let data: Data
        do {
            data = try fileSystem.contents(forPath: entry.path)
        } catch {
            return Detail(
                text: "[ERROR] cannot read \(entry.path): \(String(describing: error))",
                image: nil
            )
        }
        let header = "\(entry.path)\narchive: \(entry.archive)\n\(data.count) bytes\n\n"
        if entry.path.hasSuffix(".nif") {
            return nifDetail(header: header, path: entry.path, data: data)
        }
        if entry.path.hasSuffix(".dds") {
            return ddsDetail(header: header, path: entry.path, data: data)
        }
        return Detail(text: header + "(no preview for this file type)", image: nil)
    }

    private func nifDetail(header: String, path: String, data: Data) -> Detail {
        let file: NIFFile
        do {
            file = try NIFFile(data: data)
        } catch {
            return Detail(
                text: header + "[ERROR] NIF parse failed: \(String(describing: error))",
                image: nil
            )
        }
        let text = header + AssetInfoText.nif(file: file)
        guard let meshes else {
            return Detail(text: text + Self.noGPUNote, image: nil)
        }
        let model: RenderModel
        do {
            model = try meshes.model(path: path)
        } catch {
            let reason = String(describing: error)
            return Detail(
                text: text + "\n[WARNING] no preview image: \(reason)",
                image: nil
            )
        }
        guard let bounds = meshes.bounds(forPath: path) else {
            return Detail(text: text + "\n[WARNING] no bounds — nothing to frame", image: nil)
        }
        let scene = RenderScene(instances: [(model: model, transform: matrix_identity_float4x4)])
        let camera = SceneCamera.framing(bounds: (bounds.min, bounds.max))
        return Detail(
            text: text,
            image: renderImage(scene: scene, camera: camera, width: 1024, height: 768)
        )
    }

    private func ddsDetail(header: String, path: String, data: Data) -> Detail {
        let file: DDSFile
        do {
            file = try DDSFile(data: data)
        } catch {
            return Detail(
                text: header + "[ERROR] DDS parse failed: \(String(describing: error))",
                image: nil
            )
        }
        let text = header + AssetInfoText.dds(file: file, byteCount: data.count)
        guard let device, let textures else {
            return Detail(text: text + Self.noGPUNote, image: nil)
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
            return Detail(text: text + "\n[WARNING] no preview image: upload failed", image: nil)
        }
        let scene = RenderScene(instances: [(model: model, transform: matrix_identity_float4x4)])
        let size = Self.imageSize(width: file.width, height: file.height)
        return Detail(
            text: text,
            image: renderImage(
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

    /// Headless MTKView carries the pixel-format config Renderer reads;
    /// renderOffscreen never touches its drawable (CLI render pattern).
    private func renderImage(
        scene: RenderScene,
        camera: SceneCamera,
        width: Int,
        height: Int
    ) -> CGImage? {
        guard let device else { return nil }
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        guard
            let renderer = try? Renderer(view: view, scene: scene, camera: camera),
            let texture = try? renderer.renderOffscreen(width: width, height: height)
        else { return nil }
        return PreviewFrameImage.cgImage(from: texture)
    }
}
