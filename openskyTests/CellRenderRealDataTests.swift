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

@MainActor
private final class StreamSceneSwapErrorBox {
    var error: (any Error)?
}

@MainActor
private struct StreamHarness {
    let renderer: Renderer
    let streamer: CellStreamer
    let errorBox: StreamSceneSwapErrorBox
}

private struct StreamStats {
    let composedDrawCount: Int
    let singleDrawCount: Int
    let fraction: Double
    let filledFootprint: Double
    let afterRecenterFootprint: Double
    let series: [String]
}

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
        // Decision doc expected 16 refs / 15 drawn (STAT-only); 3.2 widened
        // base coverage to MSTT/TREE/FURN/ACTI/CONT, observed 16/16 drawn.
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

    /// Hard footprint ceiling for the streaming test (MB). Guard stays far
    /// above the measured ~450 MB 5x5 fill to tolerate debug/test overhead,
    /// but below the tools/memguard.sh watchdog so the test aborts itself with
    /// a clear failure long before the system is at risk.
    private static let footprintCapMB = 3584.0

    /// Drives the live streamer (todo 3.2) end to end over real data: a
    /// SerialCellBuildRunner builds the 5x5 around FirstRenderCell off the
    /// main thread, the sink swaps each recompose into a real Renderer, and
    /// pumping update() mirrors exactly what the app's per-frame hook does --
    /// verifying the launch path without opening a window. Also proves the
    /// memory safeguards: footprint stays bounded during the fill, and a far
    /// recenter frees the old grid (eviction) instead of doubling memory.
    /// ALWAYS run under tools/memguard.sh (see docs/engine/cell-streaming.md).
    @Test(.enabled(if: Self.canRun))
    @MainActor
    func streamsFiveByFiveGridToCompletion() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)

        let harness = try makeStreamHarness(device: device, root: root)
        let renderer = harness.renderer
        let streamer = harness.streamer

        // Phase 1: stationary at the launch cell -- the whole 5x5 streams in.
        let center = CellGridManager.cellCenter(
            of: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY)
        )
        var series: [String] = []
        var singleDrawCount = 0
        try pumpStreaming(
            harness, cameraPosition: center, label: "fill", series: &series,
            settled: {
                if streamer.residentCellCount == 1, singleDrawCount == 0 {
                    singleDrawCount = renderer.scene.drawCount
                }
                return streamer.resolvedCellCount == 25
                    && streamer.pendingCompletionCount == 0
            }
        )

        #expect(streamer.resolvedCellCount == 25, "5x5 did not fully resolve")
        #expect(streamer.failedCellCount == 0, "cells failed to build: streaming bug")
        #expect(streamer.residentCellCount + streamer.voidCellCount == 25)

        let filledFootprint = try #require(MemoryFootprint.physFootprintMB())
        let composedDrawCount = renderer.scene.drawCount
        #expect(
            composedDrawCount > singleDrawCount,
            "composed 5x5 (\(composedDrawCount)) not richer than one cell (\(singleDrawCount))"
        )

        let texture = try renderer.renderOffscreen(width: 1280, height: 720)
        let fraction = nonBackgroundFraction(pixels: readPixels(texture: texture))
        #expect(fraction > 0.02, "streamed frame is mostly background")

        // Phase 2: jump 12 cells away -- the whole old grid unloads. With
        // eviction the footprint must not double; a leak would roughly add a
        // second grid's worth on top of the first.
        let far = CellGridManager.cellCenter(
            of: CellCoordinate(x: FirstRenderCell.gridX + 12, y: FirstRenderCell.gridY)
        )
        try pumpStreaming(
            harness, cameraPosition: far, label: "recenter", series: &series,
            settled: {
                streamer.resolvedCellCount == 25 && streamer.pendingCompletionCount == 0
            }
        )
        // A few more frames so the renderer's retire list fully drains the old
        // grid's GPU resources (setScene only frees once frames prove drained).
        for _ in 0 ..< Renderer.maxFramesInFlight + 1 {
            _ = try renderer.renderOffscreen(width: 320, height: 240)
        }
        let afterRecenterFootprint = try #require(MemoryFootprint.physFootprintMB())
        let leakMessage = "recenter did not free the old grid: \(Int(filledFootprint)) -> "
            + "\(Int(afterRecenterFootprint)) MB (eviction leak?)"
        #expect(afterRecenterFootprint < filledFootprint * 1.6, "\(leakMessage)")

        try writeStreamStats(
            harness: harness,
            stats: StreamStats(
                composedDrawCount: composedDrawCount,
                singleDrawCount: singleDrawCount,
                fraction: fraction,
                filledFootprint: filledFootprint,
                afterRecenterFootprint: afterRecenterFootprint,
                series: series
            )
        )
    }
}

extension CellRenderRealDataTests {
    @MainActor
    private func makeStreamHarness(device: MTLDevice, root: GameDataRoot) throws -> StreamHarness {
        let vfs = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let provider = BuilderCellSceneProvider(
            builder: CellSceneBuilder(file: file, meshes: meshes, textures: textures),
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID
        )
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 1280, height: 720), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: RenderScene(instances: []))
        let errorBox = StreamSceneSwapErrorBox()
        let streamer = CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            runner: SerialCellBuildRunner(provider: provider),
            sink: { scene, camera in
                do {
                    try renderer.setScene(scene, camera: camera)
                } catch {
                    errorBox.error = error
                }
            }
        )
        return StreamHarness(renderer: renderer, streamer: streamer, errorBox: errorBox)
    }

    /// Pumps the streamer until `settled()` returns true, sampling the
    /// footprint each time the resident count changes and appending a curve
    /// line to `series`. Aborts (throws via #expect) the moment the footprint
    /// crosses `footprintCapMB` -- a failing test must die well before the
    /// watchdog, never lock the machine.
    @MainActor
    private func pumpStreaming(
        _ harness: StreamHarness,
        cameraPosition: SIMD3<Float>,
        label: String,
        series: inout [String],
        settled: () -> Bool
    ) throws {
        let streamer = harness.streamer
        var lastResident = -1
        _ = try harness.renderer.pumpOffscreen(width: 64, height: 64, maxFrames: 18000) {
            streamer.update(cameraPosition: cameraPosition)
            if let error = harness.errorBox.error {
                throw error
            }
            if let megabytes = MemoryFootprint.physFootprintMB() {
                if streamer.residentCellCount != lastResident {
                    lastResident = streamer.residentCellCount
                    let line = "[INFO] \(label): \(streamer.residentCellCount) resident, "
                        + "\(Int(megabytes)) MB"
                    series.append(line)
                    // Persist the curve as it grows so a footprint-cap abort
                    // still leaves the full trace on disk for diagnosis.
                    appendCurveLine(line)
                }
                let capMessage = "footprint \(Int(megabytes)) MB exceeded cap "
                    + "\(Int(Self.footprintCapMB)) MB during \(label) -- aborting before watchdog"
                try #require(megabytes < Self.footprintCapMB, "\(capMessage)")
            }
            if settled() {
                return true
            }
            // Reused targets remove allocation churn; 100 Hz polling also
            // leaves the serial builder CPU time without busy-spinning.
            Thread.sleep(forTimeInterval: 0.01)
            return false
        }
    }

    @MainActor
    private func writeStreamStats(
        harness: StreamHarness,
        stats: StreamStats
    ) throws {
        let streamer = harness.streamer
        let output = ([
            "[INFO] streamed 5x5 around (\(FirstRenderCell.gridX),\(FirstRenderCell.gridY)): "
                + "\(streamer.residentCellCount) loaded, \(streamer.voidCellCount) void",
            "[INFO] composed draw count: \(stats.composedDrawCount) "
                + "(single cell: \(stats.singleDrawCount))",
            "[INFO] streamed non-background pixels: "
                + "\(String(format: "%.1f", stats.fraction * 100))%",
            "[INFO] footprint filled: \(Int(stats.filledFootprint)) MB, "
                + "after far recenter: \(Int(stats.afterRecenterFootprint)) MB"
        ] + stats.series).joined(separator: "\n")
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try output.write(
            to: logsDirectory.appending(path: "cell-stream-5x5.log"),
            atomically: true,
            encoding: .utf8
        )
        print(output)
    }

    /// Appends one curve line to the sidecar log immediately (survives an
    /// abort). Best-effort: a failed write must not mask the real assertion.
    private func appendCurveLine(_ line: String) {
        let url = logsDirectory.appending(path: "cell-stream-5x5.log")
        try? FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data((line + "\n").utf8))
            try? handle.close()
        } else {
            try? (line + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
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
            if !dark {
                lit += 1
            }
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
