// Offscreen renderers driven by a `GameSession`, the way the app builds one.

import Metal
import OpenSkyEngineTesting
@testable import OpenSkyRendering
@testable import OpenSkyWorld

@MainActor
extension OffscreenRendererFixture {
    /// A `GameSession` and the renderer it drives, over a paused view.
    /// `shaderLibrary` nil loads the app bundle's shaders.
    public static func makeSession(
        device: MTLDevice,
        width: Int,
        height: Int,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        shaderLibrary: MTLLibrary?
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
