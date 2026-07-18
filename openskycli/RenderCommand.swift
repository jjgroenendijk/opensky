// `render`: build one exterior cell scene from the install and render it
// offscreen to a PNG — the app's launch path (docs/engine/cell-scene.md)
// minus the window, using Renderer.renderOffscreen for a deterministic
// frame. Output goes wherever --out points; engine output (our pixels), not
// extracted game data.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
import UniformTypeIdentifiers

enum RenderCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID
        let gridX = try int32(scanner.option("--x"), name: "--x") ?? FirstRenderCell.gridX
        let gridY = try int32(scanner.option("--y"), name: "--y") ?? FirstRenderCell.gridY
        let output = try scanner.requiredOption("--out")
        let size = try parseSize(scanner.option("--size"))
        let zoom = try parseZoom(scanner.option("--zoom"))
        try scanner.finish()

        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4)
        else {
            throw CLIError.failure("no Metal 4 GPU available")
        }

        let cellScene = try buildScene(
            context: context,
            device: device,
            worldspace: worldspace,
            gridX: gridX,
            gridY: gridY
        )
        print(cellScene.summary.summaryLine)
        guard let bounds = cellScene.bounds else {
            throw CLIError.failure("nothing drew — no bounds to frame a camera on")
        }

        let texture = try renderOffscreen(
            device: device,
            scene: cellScene.renderScene,
            camera: zoomed(SceneCamera.framing(bounds: bounds), zoom: zoom),
            size: size
        )
        let pixels = readPixels(texture: texture)
        let percent = String(format: "%.1f", nonBackgroundFraction(pixels: pixels) * 100)
        print("[INFO] non-background pixels: \(percent)%")
        let url = URL(filePath: output)
        try writePNG(pixels: pixels, width: size.width, height: size.height, to: url)
        print("[INFO] wrote frame -> \(url.path(percentEncoded: false))")
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

    static func buildScene(
        context: CLIContext,
        device: MTLDevice,
        worldspace: String,
        gridX: Int32,
        gridY: Int32
    ) throws -> CellScene {
        let fileSystem = context.makeFileSystem()
        let file = try context.loadSkyrimESM()
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(file: file, meshes: meshes, textures: textures)
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

    /// Headless MTKView (never shown, no window) carries the pixel-format
    /// config Renderer reads; renderOffscreen never touches its drawable.
    private static func renderOffscreen(
        device: MTLDevice,
        scene: RenderScene,
        camera: SceneCamera,
        size: (width: Int, height: Int)
    ) throws -> MTLTexture {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(view: view, scene: scene, camera: camera)
        return try renderer.renderOffscreen(width: size.width, height: size.height)
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

    private static func writePNG(
        pixels: [UInt8],
        width: Int,
        height: Int,
        to url: URL
    ) throws {
        var data = pixels
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let cgContext = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            ),
            let image = cgContext.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw CLIError.failure("cannot create PNG encoder for \(url.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CLIError.failure("cannot write PNG to \(url.path)")
        }
    }
}
