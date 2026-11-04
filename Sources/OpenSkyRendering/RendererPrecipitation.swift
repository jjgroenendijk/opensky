// Renderer precipitation setup + per-frame feed, split for size limits.

import Metal
import OpenSkyRenderCore

extension Renderer {
    public static func makeInitialScene(
        device: MTLDevice,
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
            collisionQuery: precipitationCameraRoofCheck ? frameInput.collisionQuery : nil
        ))
    }

    /// The game hides rain per drop with its occlusion map; this whole-volume check under
    /// the camera stands in only when the option is on and the GPU could not build the map.
    private var precipitationCameraRoofCheck: Bool {
        precipitationOcclusionEnabled && auxiliaryShadowUnavailable
    }
}
