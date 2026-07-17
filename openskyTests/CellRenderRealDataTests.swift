// Env-gated integration test over the user's own Skyrim SE install (read-only
// external input, never committed — AGENTS.md Legal & IP): builds the
// FirstRenderCell scene from real data, checks the load summary against the
// decision-doc expectation, renders offscreen with the framing camera, and
// dumps a PNG to logs/ for human review. Skips automatically when
// OPENSKY_DATA_ROOT is unset/unresolvable (CI has no game data) or the
// machine lacks a Metal 4 GPU.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import opensky
import Testing
import UniformTypeIdentifiers

struct CellRenderRealDataTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    /// Real data only when explicitly pointed at via the env var; the
    /// locator's Steam-default fallback is deliberately not consulted so
    /// machines without the override skip deterministically.
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func rendersFirstRenderCellFromRealInstall() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)

        let vfs = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let builder = CellSceneBuilder(file: file, meshes: meshes, textures: textures)
        let cellScene = try builder.buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX,
            gridY: FirstRenderCell.gridY
        )

        let summary = cellScene.summary
        // Decision doc expects 16 refs / 15 drawn / 1 skipped (non-STAT).
        // Loose bounds so vanilla patch-level differences do not fail here.
        #expect(summary.drawnRefCount >= 14, "too few refs drew: \(summary.summaryLine)")
        #expect(summary.totalRefCount >= summary.drawnRefCount)

        let bounds = try #require(cellScene.bounds, "no world bounds — nothing drew")
        let camera = SceneCamera.framing(bounds: bounds)

        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: cellScene.renderScene, camera: camera)
        let texture = try renderer.renderOffscreen(width: 1280, height: 720)

        let pixels = readPixels(texture: texture)
        let fraction = nonBackgroundFraction(pixels: pixels)
        // The whole-cell framing camera is conservative (enclosing sphere +
        // margin) and the cell is sparse wall segments — observed 4.3%
        // non-background on vanilla data. 2% still proves real geometry
        // shaded; near-zero means the scene went missing.
        #expect(fraction > 0.02, "frame is mostly background — scene missing?")

        let pngURL = try writePNG(pixels: pixels, width: texture.width, height: texture.height)
        try writeStats(summary: summary, fraction: fraction, pngURL: pngURL)
    }

    /// BGRA readback of the whole offscreen target.
    private func readPixels(texture: MTLTexture) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    /// Fraction of pixels that are not the black clear color (any channel
    /// above a small noise floor).
    private func nonBackgroundFraction(pixels: [UInt8]) -> Double {
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let dark = pixels[pixel] <= 8 && pixels[pixel + 1] <= 8 && pixels[pixel + 2] <= 8
            if !dark { lit += 1 }
        }
        return Double(lit) / Double(pixels.count / 4)
    }

    /// Repo root derived from this source file's location; logs/ is the
    /// designated gitignored output directory (AGENTS.md "Code scripts").
    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // openskyTests/
            .deletingLastPathComponent() // repo root
            .appending(path: "logs")
    }

    /// Summary line + pixel stats next to the PNG — print() is not captured
    /// by every test harness, the sidecar log always is on disk.
    private func writeStats(
        summary: CellLoadSummary,
        fraction: Double,
        pngURL: URL
    ) throws {
        let percent = String(format: "%.1f", fraction * 100)
        let stats = """
        \(summary.summaryLine)
        [INFO] non-background pixels: \(percent)%
        [INFO] cell render frame: \(pngURL.path)
        """
        let url = logsDirectory.appending(path: "cell-whiterunexterior06.log")
        try stats.write(to: url, atomically: true, encoding: .utf8)
        print(stats)
    }

    /// Writes the frame to logs/cell-whiterunexterior06.png (gitignored) and
    /// returns the absolute path for the stats log / human review.
    private func writePNG(pixels: [UInt8], width: Int, height: Int) throws -> URL {
        var data = pixels
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        let image = try #require(context.makeImage())
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        let url = logsDirectory.appending(path: "cell-whiterunexterior06.png")
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}
