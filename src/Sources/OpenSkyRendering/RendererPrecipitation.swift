// Renderer precipitation setup + per-frame feed, split for size limits.

public import Metal
import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRenderResources

extension Renderer {
    public static func makeInitialScene(
        device: any MTLDevice,
        requested: RenderScene?
    ) throws -> (RenderScene, PrecipitationVolume) {
        let scene = try requested ?? DemoScene.build(device: device)
        return try (scene, PrecipitationVolume(device: device))
    }

    public func updatePrecipitation(deltaTime: Float) {
        precipitation.update(PrecipitationUpdate(
            cameraPosition: frameInput.view.position,
            state: frameInput.weather?.precipitation ?? .none,
            wind: frameInput.wind,
            deltaTime: deltaTime,
            exterior: scene.sky != nil && scene.lighting == nil,
            enabled: precipitationEnabled,
            roofAbove: precipitationCameraRoofCheck ? frameInput.roofAbove : nil
        ))
    }

    /// Loads the snow record's texture, then draws snow with it and its cells.
    func preparePrecipitationLook() {
        let wanted = precipitation.tuning.snowLook
        guard wanted != precipitation.snowLook else { return }
        var texture: any MTLTexture?
        if let wanted {
            guard let recordTextures else { return }
            let loaded = recordTextures.prepare([wanted.dataPath], usage: .color)
            residencySet.addAllocations(loaded)
            texture = recordTextures.texture(wanted.dataPath)
            guard texture != nil else {
                residencySet.commit()
                return
            }
        }
        guard let swap = attempt({ try precipitation.setSnowLook(wanted, texture: texture) })
        else { return }
        // The textures stay: the generated flake and the record textures are kept.
        residencySet.removeAllocations(swap.retired.filter { !($0 is (any MTLTexture)) })
        residencySet.addAllocations(swap.added)
        residencySet.commit()
    }

    /// The game hides rain per drop with its occlusion map; this whole-volume check under
    /// the camera stands in only when the option is on and the GPU could not build the map.
    private var precipitationCameraRoofCheck: Bool {
        precipitationOcclusionEnabled && auxiliaryShadowUnavailable
    }
}
