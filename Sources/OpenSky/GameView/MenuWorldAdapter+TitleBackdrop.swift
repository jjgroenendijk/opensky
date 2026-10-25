// The title menu's logo and smoke: the loading cover layer, so the world is hidden
// while the main menu movie shows. The placement math is `TitleBackdrop`.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyWorld
import simd

extension MenuWorldAdapter {
    static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Menus"
    )

    /// While a loading screen shows, this only records the wish; the loading
    /// screen hands the view to the logo when it ends.
    func showTitleBackdrop(_ shown: Bool) {
        titleLogoView = nil
        guard let gameSession = game.gameSession else { return }
        let covering = game.loadingScreens.isCovering
        if covering {
            let camera = gameSession.freeFlyCamera
            titleLogoView = shown ? (camera.position, camera.forward) : nil
        } else {
            place(shown ? backdrop(gameSession: gameSession) : nil, gameSession: gameSession)
        }
        game.hud.setCovered(shown || covering)
    }

    /// The title menu or the opening's title sequence wants the logo.
    var titleBackdropShown: Bool {
        titleLogoView != nil
    }

    /// Puts the logo back after another cover, such as the loading screen, let go.
    /// False when no logo is wanted.
    func restoreTitleBackdrop() -> Bool {
        guard titleLogoView != nil, let gameSession = game.gameSession else { return false }
        place(backdrop(gameSession: gameSession), gameSession: gameSession)
        return true
    }

    /// The camera settles after the title opens, so the logo follows it. The loading
    /// screen owns the cover while it shows, and gives the logo back when it ends.
    func refreshTitleBackdrop() {
        guard
            !game.loadingScreens.isCovering,
            let view = titleLogoView, let gameSession = game.gameSession else { return }
        let camera = gameSession.freeFlyCamera
        guard view.eye != camera.position || view.forward != camera.forward else { return }
        place(backdrop(gameSession: gameSession), gameSession: gameSession)
    }

    /// A logo that fails to load still hides the world behind a dark screen.
    private func backdrop(gameSession: GameSession) -> TitleBackdropScene {
        do {
            return try backdropScene(gameSession: gameSession)
        } catch {
            Self.logger.error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    private func place(_ backdrop: TitleBackdropScene?, gameSession: GameSession) {
        do {
            try gameSession.renderer.setLoadingCover(
                backdrop?.placements, particles: backdrop?.particles ?? []
            )
        } catch {
            Self.logger.error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
        }
    }

    private func backdropScene(gameSession: GameSession) throws -> TitleBackdropScene {
        let renderer = gameSession.renderer
        if
            titleMeshes == nil,
            let fileSystem = game.worldData?.scriptFileSystem
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
            Self.logger.error("[ERROR] title smoke: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The logo and its smoke, drawn in place of the world.
struct TitleBackdropScene {
    var placements: [RenderPlacement]
    var particles: [ParticlePlayback]

    static let empty = TitleBackdropScene(placements: [], particles: [])
}
