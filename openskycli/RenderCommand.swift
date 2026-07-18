// `render`: build one exterior cell scene from the install and render it
// offscreen to a PNG — the app's launch path (docs/engine/cell-scene.md)
// minus the window, using Renderer.renderOffscreen for a deterministic
// frame. Output goes wherever --out points; engine output (our pixels), not
// extracted game data.

import Foundation
import Metal
import MetalKit
import simd

enum RenderCommand {
    /// Production streaming footprint: target plus two rings (5x5).
    private static let neighborOffsets: [(dx: Int32, dy: Int32)] = (-2 ... 2).flatMap { y in
        (-2 ... 2).map { x in (Int32(x), Int32(y)) }
    }

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try int32(scanner.option("--x"), name: "--x") ?? FirstRenderCell.gridX
        let gridY = try int32(scanner.option("--y"), name: "--y") ?? FirstRenderCell.gridY
        let output = try scanner.requiredOption("--out")
        let size = try parseSize(scanner.option("--size"))
        let zoom = try parseZoom(scanner.option("--zoom"))
        let neighbors = scanner.flag("--neighbors")
        try scanner.finish()

        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }

        // One shared builder so the 5x5 + LOD dedup cache residency.
        let builder = try makeBuilder(context: context, device: device)
        let cellScenes = buildCellScenes(
            builder: builder,
            worldspace: worldspace,
            gridX: gridX,
            gridY: gridY,
            neighbors: neighbors
        )
        guard !cellScenes.isEmpty else {
            throw CLIError.failure("no cells built")
        }
        guard let bounds = unionBounds(cellScenes) else {
            throw CLIError.failure("nothing drew — no bounds to frame a camera on")
        }
        let scene = try sceneWithLOD(
            builder: builder,
            cellScenes: cellScenes,
            worldspace: worldspace,
            center: CellCoordinate(x: gridX, y: gridY)
        )

        let render = try renderOffscreen(
            device: device,
            scene: scene,
            camera: zoomed(SceneCamera.framing(bounds: bounds), zoom: zoom),
            size: size
        )
        // Instancing evidence (3.2): draw calls collapse below the group +
        // terrain counts only via culling; instances >> draw calls means
        // repeated models actually batched.
        print(
            "[INFO] draw calls: \(render.stats.drawCalls) "
                + "(\(scene.drawCount) groups+terrain, \(scene.instanceCount) instances, "
                + "\(render.stats.culledInstances) culled)"
        )
        let pixels = readPixels(texture: render.texture)
        let percent = String(format: "%.1f", nonBackgroundFraction(pixels: pixels) * 100)
        print("[INFO] non-background pixels: \(percent)%")
        let url = URL(filePath: output)
        try FrameScreenshot.write(texture: render.texture, to: url)
        print("[INFO] wrote frame -> \(url.path(percentEncoded: false))")
    }

    private static func buildCellScenes(
        builder: CellSceneBuilder,
        worldspace: String,
        gridX: Int32,
        gridY: Int32,
        neighbors: Bool
    ) -> [CellScene] {
        let offsets = neighbors ? neighborOffsets : [(dx: 0, dy: 0)]
        return offsets.compactMap { offset in
            let x = gridX + offset.dx
            let y = gridY + offset.dy
            do {
                let scene = try builder.buildScene(
                    worldspaceEditorID: worldspace,
                    gridX: x,
                    gridY: y
                )
                print(scene.summary.summaryLine)
                return scene
            } catch {
                printError("[WARN] cell (\(x),\(y)) skipped: \(String(describing: error))")
                return nil
            }
        }
    }

    private static func sceneWithLOD(
        builder: CellSceneBuilder,
        cellScenes: [CellScene],
        worldspace: String,
        center: CellCoordinate
    ) throws -> RenderScene {
        let grid = CellGridManager(initialPosition: CellGridManager.cellCenter(of: center))
        let lod = try builder.buildDistantLOD(
            worldspaceEditorID: worldspace,
            center: center,
            hiddenCells: grid.desiredCells
        )
        if let lod {
            print("[INFO] distant LOD: \(lod.blockCount) blocks, "
                + "\(lod.missingBlockCount) unavailable")
        }
        var scenes = cellScenes.map(\.renderScene)
        if let lod {
            scenes.append(lod.renderScene)
        }
        return RenderScene(merging: scenes)
    }

    /// Enclosing AABB over every built cell's bounds; nil input/all-nil
    /// bounds -> nil (nothing drew anywhere).
    private static func unionBounds(
        _ cellScenes: [CellScene]
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var result: (min: SIMD3<Float>, max: SIMD3<Float>)?
        for bounds in cellScenes.compactMap(\.bounds) {
            guard let existing = result else {
                result = bounds
                continue
            }
            result = (
                min: simd_min(existing.min, bounds.min),
                max: simd_max(existing.max, bounds.max)
            )
        }
        return result
    }

    /// Shared with BenchCommand (same scene-build + option surface).
    static func int32(_ value: String?, name: String) throws -> Int32? {
        guard let value else { return nil }
        guard let parsed = Int32(value) else {
            throw CLIError.usage("\(name) expects an integer, got \(value)")
        }
        return parsed
    }

    /// "--size 1280x720" -> (1280, 720); bounded so a typo cannot ask the
    /// GPU for a texture it can never allocate.
    static func parseSize(_ value: String?) throws -> (width: Int, height: Int) {
        guard let value else { return (1280, 720) }
        let parts = value.lowercased().split(separator: "x")
        guard
            parts.count == 2,
            let width = Int(parts[0]), let height = Int(parts[1]),
            (1 ... 8192).contains(width), (1 ... 8192).contains(height)
        else {
            throw CLIError.usage("--size expects WxH (each 1-8192), got \(value)")
        }
        return (width, height)
    }

    /// The whole-cell framing camera is conservative (enclosing sphere +
    /// margin) -> sparse cells render small. `--zoom` moves the eye toward
    /// the target by that factor for a filled milestone shot; bounded so the
    /// eye cannot land on the target or behind the near plane content.
    private static func parseZoom(_ value: String?) throws -> Float {
        guard let value else { return 1 }
        guard let zoom = Float(value), (0.1 ... 10).contains(zoom) else {
            throw CLIError.usage("--zoom expects a number in 0.1-10, got \(value)")
        }
        return zoom
    }

    private static func zoomed(_ camera: SceneCamera, zoom: Float) -> SceneCamera {
        guard zoom != 1 else { return camera }
        return SceneCamera(
            eye: camera.target + (camera.eye - camera.target) / zoom,
            target: camera.target,
            sunDirection: camera.sunDirection,
            sunColor: camera.sunColor,
            ambientColor: camera.ambientColor
        )
    }

    /// Shared with BenchCommand: one cell, fresh libraries.
    static func buildScene(
        context: CLIContext,
        device: MTLDevice,
        worldspace: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> CellScene {
        let builder = try makeBuilder(context: context, device: device)
        do {
            return try builder.buildScene(
                worldspaceEditorID: worldspace,
                gridX: gridX,
                gridY: gridY
            )
        } catch let error as CellSceneError {
            throw CLIError.failure(String(describing: error))
        }
    }

    /// One VFS + ESM + MeshLibrary/TextureLibrary/CellSceneBuilder trio.
    /// Reusing one instance across multiple `buildScene` calls (the
    /// `--neighbors` grid) shares the STAT index and dedups mesh/texture
    /// residency across cells — `--neighbors` calls this once, `buildScene`
    /// calls it once per invocation.
    static func makeBuilder(context: CLIContext, device: MTLDevice) throws -> CellSceneBuilder {
        let fileSystem = context.makeFileSystem()
        let file = try context.loadSkyrimESM()
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        return CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem
        )
    }

    /// Headless MTKView (never shown, no window) carries the pixel-format
    /// config Renderer reads; renderOffscreen never touches its drawable.
    private static func renderOffscreen(
        device: MTLDevice,
        scene: RenderScene,
        camera: SceneCamera,
        size: (width: Int, height: Int)
    ) throws -> (texture: MTLTexture, stats: SceneDrawStats) {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: scene, camera: camera)
        let texture = try renderer.renderOffscreen(width: size.width, height: size.height)
        return (texture, renderer.lastDrawStats)
    }

    /// BGRA readback of the whole offscreen target.
    private static func readPixels(texture: MTLTexture) -> [UInt8] {
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

    /// Fraction of pixels not the black clear color (any channel above a
    /// small noise floor) — quick "did anything draw" signal.
    private static func nonBackgroundFraction(pixels: [UInt8]) -> Double {
        var lit = 0
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let dark = pixels[pixel] <= 8 && pixels[pixel + 1] <= 8 && pixels[pixel + 2] <= 8
            if !dark {
                lit += 1
            }
        }
        return Double(lit) / Double(pixels.count / 4)
    }
}
