// The title menu's logo and smoke: the loading cover layer, so the world is hidden
// while the main menu movie shows. The placement math is `TitleBackdrop`.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkySessionInterface
import OpenSkyWorld
import simd

extension MenuWorldAdapter {
    public func showTitleBackdrop(_ shown: Bool) {
        titleBackdrop.showTitleBackdrop(shown)
    }

    public func refreshTitleBackdrop() {
        titleBackdrop.refreshTitleBackdrop()
    }

    public var titleLighting: RenderLighting? {
        titleBackdrop.titleLighting
    }
}

/// The title backdrop and the state it keeps between frames.
final class MenuTitleBackdrop {
    let game: any MenuWorldHost
    /// Built on first use, because it walks the install.
    var titleMeshes: MeshLibrary?
    /// The camera the logo was placed for, while the title backdrop shows.
    var titleLogoView: (eye: SIMD3<Float>, forward: SIMD3<Float>)?

    init(game: any MenuWorldHost) {
        self.game = game
    }

    func showTitleBackdrop(_ shown: Bool) {
        titleLogoView = nil
        guard let gameSession = game.gameSession else { return }
        place(shown ? backdrop(gameSession: gameSession) : nil, gameSession: gameSession)
    }

    /// The camera settles after the title opens, so the logo follows it. The loading
    /// screen owns the cover while it shows.
    func refreshTitleBackdrop() {
        guard
            !game.loadingScreens.isCovering,
            let view = titleLogoView, let gameSession = game.gameSession else { return }
        let camera = gameSession.freeFlyCamera
        guard view.eye != camera.position || view.forward != camera.forward else { return }
        place(backdrop(gameSession: gameSession), gameSession: gameSession)
    }

    /// A logo that fails to load still hides the world behind a dark screen.
    private func backdrop(gameSession: any GameSessionPort) -> TitleBackdropScene {
        do {
            return try backdropScene(gameSession: gameSession)
        } catch {
            MenusLog.logger
                .error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    private func place(_ backdrop: TitleBackdropScene?, gameSession: any GameSessionPort) {
        do {
            try gameSession.renderer.setLoadingCover(
                backdrop?.placements,
                particles: backdrop?.particles ?? [],
                lighting: backdrop.flatMap { _ in titleLighting }
            )
        } catch {
            MenusLog.logger
                .error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
        }
    }

    /// The game draws the logo in `MainMenuCell`, so it takes that cell's light.
    var titleLighting: RenderLighting? {
        game.menuRecords?.menuRecords?.mainMenuLighting.flatMap {
            CellSceneBuilder.renderLighting(cell: $0.cell, template: $0.template)
        }
    }

    private func backdropScene(gameSession: any GameSessionPort) throws -> TitleBackdropScene {
        let renderer = gameSession.renderer
        if
            titleMeshes == nil,
            let fileSystem = game.menuRecords?.scriptFileSystem
        {
            let textures = try TextureLibrary(fileSystem: fileSystem, device: renderer.device)
            titleMeshes = MeshLibrary(
                fileSystem: fileSystem, device: renderer.device, textures: textures
            )
        }
        let path = TitleBackdrop.logoPath
        guard let meshes = titleMeshes else { return .empty }
        let model = try meshes.model(path: path)
        guard let bounds = meshes.bounds(forPath: path) else { return .empty }
        let camera = gameSession.freeFlyCamera
        titleLogoView = (camera.position, camera.forward)
        let view = TitleBackdrop.View(
            eye: camera.position, forward: camera.forward, right: camera.right
        )
        let logo = TitleBackdrop.Box(min: bounds.min, max: bounds.max)
        var scene = TitleBackdropScene(
            placements: [RenderPlacement(
                model: model, transform: TitleBackdrop.logoTransform(view: view, logo: logo),
                castsShadows: false, layer: .loadingCover
            )],
            particles: []
        )
        addFog(to: &scene, meshes: meshes) {
            TitleBackdrop.fogTransform(view: view, logo: logo, fog: $0)
        }
        return scene
    }

    /// The logo still shows when the smoke fails to load.
    private func addFog(
        to scene: inout TitleBackdropScene,
        meshes: MeshLibrary,
        transform placing: (TitleBackdrop.Box) -> float4x4
    ) {
        let path = TitleBackdrop.fogPath
        do {
            let model = try meshes.model(path: path)
            guard let bounds = meshes.bounds(forPath: path) else { return }
            let transform = placing(TitleBackdrop.Box(min: bounds.min, max: bounds.max))
            scene.placements.append(RenderPlacement(
                model: model, transform: transform, castsShadows: false, layer: .loadingCover
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

/// The logo and its smoke, drawn in place of the world.
struct TitleBackdropScene {
    var placements: [RenderPlacement]
    var particles: [ParticlePlayback]

    static let empty = TitleBackdropScene(placements: [], particles: [])
}
