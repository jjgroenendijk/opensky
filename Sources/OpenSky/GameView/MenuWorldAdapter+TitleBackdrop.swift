// The title menu's logo scene: the loading cover layer, so the world is hidden
// while the main menu movie shows. The placement math is `TitleBackdrop`.

import Foundation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyWorld

extension MenuWorldAdapter {
    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "Menus"
    )

    func showTitleBackdrop(_ shown: Bool) {
        titleLogoView = nil
        guard let gameSession = game.gameSession else { return }
        place(shown ? logo(gameSession: gameSession) : nil, gameSession: gameSession)
    }

    /// The camera settles after the title opens, so the logo follows it.
    func refreshTitleBackdrop() {
        guard let view = titleLogoView, let gameSession = game.gameSession else { return }
        let camera = gameSession.freeFlyCamera
        guard view.eye != camera.position || view.forward != camera.forward else { return }
        place(logo(gameSession: gameSession), gameSession: gameSession)
    }

    /// A logo that fails to load still hides the world behind a dark screen.
    private func logo(gameSession: GameSession) -> [RenderPlacement] {
        do {
            return try logoPlacements(gameSession: gameSession)
        } catch {
            Self.logger.error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func place(_ placements: [RenderPlacement]?, gameSession: GameSession) {
        do {
            try gameSession.renderer.setLoadingCover(placements)
        } catch {
            Self.logger.error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
        }
    }

    private func logoPlacements(gameSession: GameSession) throws -> [RenderPlacement] {
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
        guard let meshes = titleMeshes else { return [] }
        let model = try meshes.model(path: path)
        guard let bounds = meshes.bounds(forPath: path) else { return [] }
        let camera = gameSession.freeFlyCamera
        titleLogoView = (camera.position, camera.forward)
        let transform = TitleBackdrop.transform(
            eye: camera.position, forward: camera.forward, right: camera.right,
            boundsMin: bounds.min, boundsMax: bounds.max
        )
        return [RenderPlacement(
            model: model, transform: transform, castsShadows: false, layer: .loadingCover
        )]
    }
}
