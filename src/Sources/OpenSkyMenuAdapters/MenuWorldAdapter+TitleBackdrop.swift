// The title menu's logo and smoke: the loading cover layer, so the world is hidden
// while the main menu movie shows, drawn in the loading screen's own scene.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkySessionInterface
import simd

extension MenuWorldAdapter {
    public func showTitleBackdrop(_ shown: Bool) {
        titleBackdrop.showTitleBackdrop(shown)
    }

    public func refreshTitleBackdrop() {
        titleBackdrop.refreshTitleBackdrop()
    }
}

/// The title backdrop and the state it keeps between frames.
final class MenuTitleBackdrop {
    let game: any MenuWorldHosts
    /// Built on first use, because it walks the install.
    var titleMeshes: MeshLibrary?
    /// Whether the title asked for the backdrop, and whether it reached the renderer.
    private(set) var isWanted = false
    private(set) var isPlaced = false

    init(game: any MenuWorldHosts) {
        self.game = game
    }

    func showTitleBackdrop(_ shown: Bool) {
        isWanted = shown
        isPlaced = false
        guard let renderer = game.renderer else { return }
        place(shown ? backdrop(renderer: renderer) : nil, renderer: renderer)
    }

    /// Places the backdrop when the title asked for it before a session existed. The
    /// loading screen owns the cover while it shows.
    func refreshTitleBackdrop() {
        guard
            isWanted, !isPlaced, !game.loadingScreens.isCovering,
            let renderer = game.renderer else { return }
        place(backdrop(renderer: renderer), renderer: renderer)
    }

    /// A logo that fails to load still hides the world behind a dark screen.
    private func backdrop(renderer: any RendererPort) -> LoadingCoverScene {
        var scene: LoadingCoverScene
        do {
            scene = try backdropScene(renderer: renderer)
        } catch {
            MenusLog.logger
                .error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
            scene = Self.emptyScene
        }
        scene.imageSpace = game.menuRecords?.loadScreenImageSpace
        return scene
    }

    private func place(_ backdrop: LoadingCoverScene?, renderer: any RendererPort) {
        do {
            try renderer.setLoadingScene(backdrop)
            isPlaced = backdrop != nil
        } catch {
            MenusLog.logger
                .error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
        }
    }

    /// The loading screen's scene with no model: its camera and lights on black.
    static var emptyScene: LoadingCoverScene {
        LoadingCoverScene(
            placements: [], pointLights: LoadingScreenScene.lights,
            lighting: LoadingScreenScene.lighting,
            camera: LoadingCoverCamera(
                view: LoadingScreenScene.camera(),
                horizontalFieldOfView: LoadingScreenScene.horizontalFieldOfView(
                    LoadingScreenScene.defaultFieldOfView
                )
            )
        )
    }

    private func backdropScene(renderer: any RendererPort) throws -> LoadingCoverScene {
        if
            titleMeshes == nil,
            let fileSystem = game.menuRecords?.scriptFileSystem
        {
            let textures = try TextureLibrary(fileSystem: fileSystem, device: renderer.device)
            titleMeshes = MeshLibrary(
                fileSystem: fileSystem, device: renderer.device, textures: textures
            )
        }
        var scene = Self.emptyScene
        guard let meshes = titleMeshes else { return scene }
        addMist(to: &scene, meshes: meshes)
        let path = TitleBackdrop.logoPath
        let pose = try LoadingScreenScene.ModelPose(
            rotationDegrees: .zero, scale: 1, translation: .zero,
            markerRotation: markerRotation(of: path)
        )
        try scene.placements.append(RenderPlacement(
            model: meshes.model(path: path),
            transform: LoadingScreenScene.modelTransform(
                pose, aspectRatio: renderer.drawableAspectRatio
            ),
            castsShadows: true, layer: .loadingCover
        ))
        return scene
    }

    /// The logo's inventory marker turn, which the game adds as it does for a loading
    /// screen model.
    private func markerRotation(of path: String) throws -> SIMD3<Float>? {
        guard let files = game.menuRecords?.scriptFileSystem else { return nil }
        return try NIFFile(data: files.contents(forPath: path)).inventoryMarker?.rotation
    }

    /// The logo still shows when the smoke fails to load.
    private func addMist(to scene: inout LoadingCoverScene, meshes: MeshLibrary) {
        let path = LoadingScreenScene.mistPath
        let transform = LoadingScreenScene.mistTransform
        do {
            try scene.placements.append(RenderPlacement(
                model: meshes.model(path: path), transform: transform,
                castsShadows: false, layer: .loadingCover
            ))
            scene.particles = try meshes.particlePlaybacks(
                path: path, placementTransform: transform, formID: 0
            )
        } catch {
            MenusLog.logger
                .error("[ERROR] title smoke: \(String(describing: error), privacy: .public)")
        }
    }
}
