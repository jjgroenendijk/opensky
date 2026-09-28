// Renderer precipitation setup + per-frame feed, split for size limits.

import Metal

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
            cameraPosition: freeFlyCamera.position,
            state: currentResolvedWeather?.precipitation ?? .none,
            wind: currentWind,
            deltaTime: deltaTime,
            exterior: scene.sky != nil && scene.lighting == nil,
            enabled: precipitationEnabled,
            collisionQuery: collisionQuery
        ))
    }
}
