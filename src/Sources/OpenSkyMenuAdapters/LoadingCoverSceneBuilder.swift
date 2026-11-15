import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import simd

/// Builds the loading screen's scene for `LoadingScreenPresentationAdapter`.
struct LoadingCoverSceneBuilder {
    let game: any LoadingScreenPresentationHost
    let state: LoadingScreenPartState

    /// The game's scene for `frame`: its camera, its lights, the mist, and the model.
    func coverScene(
        _ frame: LoadingCoverFrame,
        renderer: any RendererPort
    ) -> LoadingCoverScene {
        var scene = LoadingCoverScene(
            placements: [], pointLights: LoadingScreenScene.lights,
            lighting: LoadingScreenScene.lighting,
            camera: LoadingCoverCamera(
                view: LoadingScreenScene.camera(pathNode: cameraPathNode(frame)),
                horizontalFieldOfView: LoadingScreenScene.horizontalFieldOfView(frame.fieldOfView)
            )
        )
        guard let meshes = meshLibrary(renderer: renderer) else { return scene }
        let mist = mist(meshes: meshes)
        scene.placements = mist?.placements ?? []
        scene.particles = mist?.particles ?? []
        scene.placements += placement(
            frame,
            meshes: meshes,
            aspectRatio: renderer.drawableAspectRatio
        )
        return scene
    }

    private func meshLibrary(renderer: any RendererPort) -> MeshLibrary? {
        if
            state.meshes == nil,
            let fileSystem = game.menuRecords?.scriptFileSystem
        {
            let textures = attempt {
                try TextureLibrary(fileSystem: fileSystem, device: renderer.device)
            }
            state.meshes = textures.map {
                MeshLibrary(fileSystem: fileSystem, device: renderer.device, textures: $0)
            }
        }
        return state.meshes
    }

    private func placement(
        _ frame: LoadingCoverFrame, meshes: MeshLibrary, aspectRatio: Float
    ) -> [RenderPlacement] {
        guard let path = frame.model, !state.failedModels.contains(path) else { return [] }
        do {
            let model = try meshes.model(path: path)
            let marker = InventoryItemPreview.meshPath(path)
                .flatMap { state.modelMarkers?.value(for: $0) }
            let pose = frame.modelPose(markerRotation: marker?.rotation)
            return [RenderPlacement(
                model: model,
                transform: LoadingScreenScene.modelTransform(pose, aspectRatio: aspectRatio),
                castsShadows: true,
                layer: .loadingCover
            )]
        } catch {
            state.failedModels.insert(path)
            LoadingScreenLog.logger
                .warning("[WARNING] loading screen model failed: \(path, privacy: .public)")
            return []
        }
    }

    /// The mist, built once per cover so its particles run on. The model still
    /// shows when the mist fails to load.
    private func mist(meshes: MeshLibrary) -> LoadingMist? {
        if let mist = state.mist {
            return mist
        }
        let path = LoadingScreenScene.mistPath
        guard !state.failedModels.contains(path) else { return nil }
        do {
            let transform = LoadingScreenScene.mistTransform
            let mist = try LoadingMist(
                placements: [RenderPlacement(
                    model: meshes.model(path: path), transform: transform,
                    castsShadows: false, layer: .loadingCover
                )],
                particles: meshes.particlePlaybacks(
                    path: path, placementTransform: transform, formID: 0
                )
            )
            state.mist = mist
            return mist
        } catch {
            state.failedModels.insert(path)
            LoadingScreenLog.logger
                .warning("[WARNING] loading screen mist failed: \(path, privacy: .public)")
            return nil
        }
    }

    private func cameraPathNode(_ frame: LoadingCoverFrame) -> SIMD3<Float> {
        guard let path = frame.cameraPath, let track = state.cameraPaths?.value(for: path) else {
            return .zero
        }
        return track.nodePosition(after: frame.elapsedSeconds)
    }
}
