// `swf render-sweep`: the GPU half of the milestone 8.2.4 gate. One renderer
// is built over the synthetic demo scene, a movie-free baseline frame is
// captured, and then every vanilla Interface movie is assigned in turn and
// rendered through the production display-list layer. Per movie it reports
// the draw stats and how much of the frame the movie actually changed, so a
// silently empty layer cannot pass. Any decode/render error fails the gate.
//
// Frames stay in memory unless `--out <dir>` is given; rendered vanilla movies
// embed game art, so captures belong under logs/ (gitignored), never in the
// repository (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
import MetalKit

enum SWFRenderSweep {
    /// Fixed animation time: the demo scene is identical across renders, so
    /// every pixel difference from the baseline comes from the SWF layer.
    private static let animationTime: Float = 1
    /// Per-channel delta above which a pixel counts as changed.
    private static let channelThreshold = 8

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let size = try RenderCommand.parseSize(scanner.option("--size"))
        let outputDirectory = try scanner.option("--out")
        // Substring filter so one movie can be captured on its own; the
        // shared glyph atlas fills up over a 53-movie run, so a single-movie
        // pass is the honest per-movie glyph count.
        let filter = try scanner.option("--movie")?.lowercased()
        try scanner.finish()
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }
        let loader = SWFMovieLoader(fileSystem: context.makeFileSystem())
        let paths = loader.moviePaths()
            .filter { filter.map($0.contains) ?? true }
        guard !paths.isEmpty else {
            throw CLIError.failure("no interface\\*.swf movies matched")
        }
        var sweep = try Sweep(device: device, size: size, outputDirectory: outputDirectory)
        for path in paths {
            sweep.render(path: path, loader: loader)
        }
        sweep.printReport(total: paths.count)
        guard sweep.failures.isEmpty else {
            throw CLIError.failure(
                "swf render-sweep failed: \(sweep.failures.count) movies did not render"
            )
        }
    }

    /// Holds the renderer + baseline frame across the movie loop.
    private struct Sweep {
        let renderer: Renderer
        let size: (width: Int, height: Int)
        let outputDirectory: URL?
        let baseline: [UInt8]
        var rendered = 0
        var blankFrames = 0
        var drawCalls = 0
        var triangles = 0
        var glyphs = 0
        var maskDraws = 0
        var skippedItems = 0
        var unresolvedFonts = 0
        var failures: [String] = []

        init(
            device: MTLDevice,
            size: (width: Int, height: Int),
            outputDirectory: String?
        ) throws {
            let view = MTKView(
                frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
                device: device
            )
            view.isPaused = true
            view.enableSetNeedsDisplay = false
            renderer = try Renderer(view: view)
            self.size = size
            if let directory = outputDirectory {
                let url = URL(filePath: directory, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(
                    at: url, withIntermediateDirectories: true
                )
                self.outputDirectory = url
            } else {
                self.outputDirectory = nil
            }
            baseline = try Self.pixels(
                of: renderer.renderOffscreen(
                    width: size.width, height: size.height, animationTime: animationTime
                ),
                size: size
            )
        }

        mutating func render(path: String, loader: SWFMovieLoader) {
            do {
                let scene = try loader.load(path: path)
                unresolvedFonts += scene.unresolvedFontNames.count
                try renderer.setSWFMovie(scene)
                let texture = try renderer.renderOffscreen(
                    width: size.width, height: size.height, animationTime: animationTime
                )
                let stats = renderer.lastSWFDrawStats
                let changed = try Self.changedPixels(baseline, Self.pixels(of: texture, size: size))
                record(stats: stats, changed: changed, path: path)
                try write(texture: texture, path: path)
            } catch {
                failures.append(path)
                printError("[ERROR] \(path): \(String(describing: error))")
            }
        }

        private mutating func record(stats: SWFDrawStats, changed: Int, path: String) {
            rendered += 1
            drawCalls += stats.drawCalls
            triangles += stats.triangles
            glyphs += stats.glyphs
            maskDraws += stats.maskDraws
            skippedItems += stats.skippedItems
            if changed == 0 {
                blankFrames += 1
            }
            print(
                "[INFO] \(path): \(stats.drawCalls) draws, \(stats.triangles) triangles, "
                    + "\(stats.glyphs) glyphs, \(stats.maskDraws) mask draws, "
                    + "\(stats.skippedItems) skipped, \(changed) pixels changed"
            )
        }

        private func write(texture: MTLTexture, path: String) throws {
            guard let outputDirectory else { return }
            let name = (path as NSString).lastPathComponent
                .replacingOccurrences(of: "\\", with: "_")
            let url = outputDirectory.appending(path: name + ".png")
            try FrameScreenshot.write(texture: texture, to: url)
        }

        func printReport(total: Int) {
            print(
                "[INFO] swf render-sweep: \(total) movies, \(rendered) rendered, "
                    + "\(blankFrames) unchanged frames, \(failures.count) failed"
            )
            print(
                "[INFO] swf render-sweep draws: \(drawCalls) draws, \(triangles) triangles, "
                    + "\(glyphs) glyphs, \(maskDraws) mask draws, \(skippedItems) skipped, "
                    + "\(unresolvedFonts) unresolved font names"
            )
        }

        private static func pixels(
            of texture: MTLTexture,
            size: (width: Int, height: Int)
        ) throws -> [UInt8] {
            var pixels = [UInt8](repeating: 0, count: size.width * size.height * 4)
            pixels.withUnsafeMutableBytes { bytes in
                guard let base = bytes.baseAddress else { return } // non-empty
                texture.getBytes(
                    base,
                    bytesPerRow: size.width * 4,
                    from: MTLRegionMake2D(0, 0, size.width, size.height),
                    mipmapLevel: 0
                )
            }
            return pixels
        }

        private static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
            var changed = 0
            for pixel in stride(from: 0, to: min(lhs.count, rhs.count), by: 4) {
                let delta = (0 ..< 3)
                    .map { abs(Int(lhs[pixel + $0]) - Int(rhs[pixel + $0])) }
                    .max() ?? 0
                if delta > channelThreshold {
                    changed += 1
                }
            }
            return changed
        }
    }
}
