// Offscreen renderers driven by a `GameSession`, the way the app builds one.

public import Metal
public import OpenSkyEngineTesting
public import OpenSkyRenderCore
@testable public import OpenSkyRendering
@testable public import OpenSkyWorld

@MainActor
extension OffscreenRendererFixture {
    /// A `GameSession` and the renderer it drives, over a paused view.
    /// `shaderLibrary` nil loads the app bundle's shaders.
    public static func makeSession(
        device: any MTLDevice,
        width: Int,
        height: Int,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        shaderLibrary: any MTLLibrary?
    ) throws -> GameSession {
        try GameSession(
            view: pausedView(device: device, width: width, height: height),
            scene: scene, camera: camera, shaderLibrary: shaderLibrary
        )
    }
}

@MainActor
extension OffscreenCanvas {
    public func makeSession() throws -> GameSession {
        let (device, library) = try resources()
        return try OffscreenRendererFixture.makeSession(
            device: device, width: width, height: height, shaderLibrary: library
        )
    }
}
