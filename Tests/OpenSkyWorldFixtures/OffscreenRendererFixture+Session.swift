// Offscreen renderers driven by a `GameSession`, the way the app builds one.

import EngineTesting
import Metal
@testable import OpenSkyRendering
@testable import OpenSkyWorld

extension OffscreenRendererFixture {
    /// A renderer over a paused view with a `GameSession` as its frame driver.
    /// `shaderLibrary` nil loads the app bundle's shaders.
    @MainActor
    public static func makeSessionRenderer(
        device: MTLDevice,
        width: Int,
        height: Int,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        shaderLibrary: MTLLibrary?
    ) throws -> Renderer {
        try Renderer(
            view: pausedView(device: device, width: width, height: height),
            scene: scene, camera: camera, shaderLibrary: shaderLibrary
        )
    }
}

extension OffscreenCanvas {
    @MainActor
    public func makeSessionRenderer() throws -> Renderer {
        let (device, library) = try resources()
        return try OffscreenRendererFixture.makeSessionRenderer(
            device: device, width: width, height: height, shaderLibrary: library
        )
    }
}
