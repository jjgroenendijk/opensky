// The title menu's logo scene: the loading cover layer, so the world is hidden
// while the main menu movie shows. The placement math is `TitleBackdrop`.

import Foundation
import OpenSkyFormatsCore
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import OSLog

extension MenuWorldAdapter {
    private static let logger = Logger(subsystem: "nl.jjgroenendijk.opensky", category: "Menus")

    func showTitleBackdrop(_ shown: Bool) {
        titleLogoView = nil
        guard let renderer = game.renderer else { return }
        place(shown ? logo(renderer: renderer) : nil, renderer: renderer)
    }

    /// The camera settles after the title opens, so the logo follows it.
    func refreshTitleBackdrop() {
        guard let view = titleLogoView, let renderer = game.renderer else { return }
        let camera = renderer.freeFlyCamera
        guard view.eye != camera.position || view.forward != camera.forward else { return }
        place(logo(renderer: renderer), renderer: renderer)
    }

    /// A logo that fails to load still hides the world behind a dark screen.
    private func logo(renderer: Renderer) -> [RenderPlacement] {
        do {
            return try logoPlacements(renderer: renderer)
        } catch {
            Self.logger.error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    private func place(_ placements: [RenderPlacement]?, renderer: Renderer) {
        do {
            try renderer.setLoadingCover(placements)
        } catch {
            Self.logger.error("[ERROR] title logo: \(String(describing: error), privacy: .public)")
        }
    }

    private func logoPlacements(renderer: Renderer) throws -> [RenderPlacement] {
        if
            titleMeshes == nil,
            let fileSystem = (game.worldData as? ScriptDataProviding)?.scriptFileSystem
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
        let camera = renderer.freeFlyCamera
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
