import OpenSkyRendering

extension Renderer {
    /// Renders one frame, which starts the MetalFX scaler build, then waits for the build.
    /// The next frame upscales.
    public func settleUpscaler(width: Int, height: Int) async throws {
        _ = try renderOffscreen(width: width, height: height)
        await upscalerBuildFinished()
    }
}
