// The turning 3D item in the inventory menu: the selected row's ground model, drawn as
// a menu scene in front of the world and turned about its up axis. The model is drawn
// unlit, with its diffuse texture. See docs/engine/inventory-menu.md.

import Foundation
@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyRenderResources
import simd

/// Which model the preview shows and how far it has turned. Pure, so tests drive it.
nonisolated public struct InventoryItemPreview: Equatable, Sendable {
    /// Radians per second. No source gives the game's rate; one turn takes about 10 s.
    public static let turnRate: Float = 0.6
    public static let fovYRadians: Float = 40 * .pi / 180
    /// The depth share the item draws into, nearer than the first-person arms' 0.02.
    public static let depthSlice: Float = 0.005
    /// The model's bounding sphere is scaled to this radius in front of the camera.
    static let radius: Float = 0.75
    static let eye = SIMD3<Float>(0, -3.2, 0.4)
    /// Right of the screen centre, beside the item list.
    static let centre = SIMD3<Float>(0.85, 0, 0)

    public private(set) var modelPath: String?
    public private(set) var yaw: Float = 0
    private var lastTick: Double?

    public init() {}

    /// Shows `path`, a ground model under `meshes\`. A new model starts unturned.
    public mutating func show(_ path: String?) {
        let normalized = path.flatMap(Self.meshPath)
        guard normalized != modelPath else { return }
        modelPath = normalized
        yaw = 0
        lastTick = nil
    }

    public mutating func tick(now: Double) {
        defer { lastTick = now }
        guard let lastTick, modelPath != nil else { return }
        let step = Float(max(0, min(now - lastTick, 0.25))) * Self.turnRate
        yaw = (yaw + step).truncatingRemainder(dividingBy: 2 * .pi)
    }

    /// An item record's MODL path is relative to `meshes\`.
    static func meshPath(_ path: String) -> String? {
        guard let normalized = try? VirtualFileSystem.normalize(path), !normalized.isEmpty else {
            return nil
        }
        return normalized.hasPrefix("meshes\\") ? normalized : "meshes\\" + normalized
    }

    /// Turns the model by its `BSInvMarker`, centres and scales `bounds` (taken after
    /// that turn) so it fits, times the marker's zoom, then turns it by `yaw`.
    public static func placement(
        bounds: (min: SIMD3<Float>, max: SIMD3<Float>),
        yaw: Float,
        marker: NIFInventoryMarker? = nil
    ) -> float4x4 {
        let middle = (bounds.min + bounds.max) / 2
        let reach = simd_length(bounds.max - bounds.min) / 2
        let zoom = marker.map { $0.zoom > 0 ? $0.zoom : 1 } ?? 1
        let scale = (reach > .ulpOfOne ? radius / reach : 1) * zoom
        return MatrixMath.translation(centre)
            * float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 0, 1)))
            * MatrixMath.scale(uniform: scale)
            * MatrixMath.translation(-middle)
            * float4x4(marker?.orientation ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
    }
}

/// Loads preview models off the main actor and keeps the last few built.
public final class InventoryItemPreviewSource {
    static let keptModels = 8

    private let files: AssetLoader<String, NIFFile>
    private let fileSystem: any GameFileSource
    private var textures: TextureLibrary?
    private var built: [String: PreviewModel] = [:]
    private var order: [String] = []
    public private(set) var failures: [String: String] = [:]

    /// `immediate` loads inside the request, for tests and tools.
    public init(fileSystem: any GameFileSource, immediate: Bool = false) {
        let load: @Sendable (String) throws -> NIFFile = { path in
            try NIFFile(data: fileSystem.contents(forPath: path))
        }
        files = immediate
            ? AssetLoader(worker: ImmediateAssetLoadWorker(load: load))
            : AssetLoader(load: load)
        self.fileSystem = fileSystem
    }

    /// The scene for `preview`, or nil while its model loads, after a failure, or with
    /// no model to show.
    public func scene(for preview: InventoryItemPreview, device: MTLDevice) -> MenuScene? {
        guard let path = preview.modelPath, let entry = model(path, device: device) else {
            return nil
        }
        let placement = InventoryItemPreview.placement(
            bounds: entry.bounds, yaw: preview.yaw, marker: entry.marker
        )
        var scene = MenuScene(
            eye: InventoryItemPreview.eye, target: InventoryItemPreview.centre,
            up: SIMD3(0, 0, 1), fovYRadians: InventoryItemPreview.fovYRadians
        )
        scene.draws = entry.model.draws(
            playing: [], placement: placement, eye: scene.eye, up: scene.up
        )
        scene.frontDepthSlice = InventoryItemPreview.depthSlice
        return scene
    }

    private func model(_ path: String, device: MTLDevice) -> PreviewModel? {
        if let entry = built[path] {
            return entry
        }
        guard failures[path] == nil else { return nil }
        files.prefetch(path)
        files.drain()
        switch files.state(of: path) {
        case .loading:
            return nil
        case let .failed(error):
            failures[path] = String(describing: error)
            return nil
        case let .ready(file):
            do {
                let library = try textures ?? TextureLibrary(fileSystem: fileSystem, device: device)
                textures = library
                let model = try MenuSceneModel(
                    file: file,
                    device: device,
                    textures: library.provider
                )
                let marker = file.inventoryMarker
                guard let bounds = Self.bounds(of: model, turnedBy: marker?.orientation) else {
                    failures[path] = "no shape to draw"
                    return nil
                }
                let entry = PreviewModel(model: model, bounds: bounds, marker: marker)
                keep(path, entry)
                return entry
            } catch {
                failures[path] = String(describing: error)
                return nil
            }
        }
    }

    private func keep(_ path: String, _ entry: PreviewModel) {
        built[path] = entry
        order.append(path)
        while order.count > Self.keptModels {
            built[order.removeFirst()] = nil
        }
    }

    /// The box around every visible vertex in model space, after `turn`.
    static func bounds(
        of model: MenuSceneModel,
        turnedBy turn: simd_quatf? = nil
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        let rotation = float4x4(turn ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
        let pose = NIFEffectPose(scene: model.scene, playing: [])
        var low = SIMD3<Float>(repeating: .infinity)
        var high = SIMD3<Float>(repeating: -.infinity)
        for state in pose.shapes(of: model.scene) where state.isVisible {
            for position in model.scene.shapes[state.shape].positions {
                let point = rotation * state.transform * SIMD4(position, 1)
                let world = SIMD3(point.x, point.y, point.z)
                low = simd_min(low, world)
                high = simd_max(high, world)
            }
        }
        return low.x.isFinite && high.x.isFinite ? (low, high) : nil
    }

    private struct PreviewModel {
        let model: MenuSceneModel
        let bounds: (min: SIMD3<Float>, max: SIMD3<Float>)
        let marker: NIFInventoryMarker?
    }
}
