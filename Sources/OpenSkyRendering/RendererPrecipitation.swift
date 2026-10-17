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
            cameraPosition: frameInput.view.position,
            state: frameInput.weather?.precipitation ?? .none,
            wind: frameInput.wind,
            deltaTime: deltaTime,
            exterior: scene.sky != nil && scene.lighting == nil,
            enabled: precipitationEnabled,
            collisionQuery: frameInput.collisionQuery
        ))
    }
}
