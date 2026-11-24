// `swf movie-probe --out`: the probed movie runs inside an offscreen renderer, so
// the stage after the steps can be drawn to a PNG. The picture holds game art,
// so it belongs in gitignored .logs/.

import Foundation
import Metal
import MetalKit
import OpenSkyCLIArguments
import OpenSkyFormatsSWF
import OpenSkyRendering
import OpenSkyRenderResources

struct SWFProbePicture {
    static let width = 1280
    static let height = 720

    let renderer: Renderer
    let runtime: SWFMovieRuntime

    init(scene: SWFMovieScene, prepare: @escaping (SWFMovieRuntime) -> Void) throws {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: Self.width, height: Self.height), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        renderer = try Renderer(rendering: view)
        guard
            try renderer.startMenuMovie(scene, prepare: prepare),
            let runtime = renderer.swfRuntime
        else {
            throw CLIError.failure("the movie's runtime did not start")
        }
        self.runtime = runtime
    }

    /// Pushes what the steps changed, then draws one frame.
    func write(to url: URL) throws {
        try renderer.advanceSWFRuntime()
        let texture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try FrameScreenshot.write(texture: texture, to: url)
    }
}
