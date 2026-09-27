// Offscreen smoke render of the full static-mesh path: real Renderer, real
// MTKView drawable (no window), real DemoScene. Deterministic pixel checks
// (AGENTS.md testing rule) plus a temp PNG for human eyes — logged so
// renderer changes stay visually verifiable without Screen Recording TCC.
// Skips when the machine lacks a Metal 4 GPU (paravirtual CI).

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

private struct EnvironmentRender {
    let pixels: [UInt8]
    let width: Int
    let height: Int
    let stats: SceneDrawStats
}

struct RendererOffscreenTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func rendersDemoSceneOffscreen() throws {
        let device = try #require(Self.device)
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 480, height: 320), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false

        let renderer = try Renderer(view: view)
        // Synchronous offscreen frame — no window, no drawable, no timing
        // races. Render twice to prove the ring/event bookkeeping survives
        // consecutive frames.
        _ = try renderer.renderOffscreen(width: 480, height: 320)
        let texture = try renderer.renderOffscreen(width: 480, height: 320)

        let width = texture.width
        let height = texture.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return } // non-empty
            texture.getBytes(
                base,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }

        // The scene must actually shade: more distinct colors than clear +
        // a flat silhouette could produce, and the checkerboard ground must
        // put lit geometry in the frame center.
        var distinct = Set<UInt32>()
        for pixel in stride(from: 0, to: pixels.count, by: 4) {
            let bgra = UInt32(pixels[pixel]) << 24 | UInt32(pixels[pixel + 1]) << 16
                | UInt32(pixels[pixel + 2]) << 8 | UInt32(pixels[pixel + 3])
            distinct.insert(bgra)
        }
        #expect(distinct.count > 50, "rendered frame is too uniform — scene missing?")

        let center = ((height / 2) * width + width / 2) * 4
        let centerIsClearColor = pixels[center] == 0 && pixels[center + 1] == 0
            && pixels[center + 2] == 0
        #expect(!centerIsClearColor, "frame center is background — no geometry drawn")

        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-offscreen-\(UUID().uuidString).png")
        try FrameScreenshot.write(texture: texture, to: url)
        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        print("[INFO] offscreen frame: \(url.path)")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func appWorldWritesScreenshot() throws {
        let controller = GameViewController()
        _ = controller.view // load renderer through production app wiring
        let url = FileManager.default.temporaryDirectory
            .appending(path: "opensky-app-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        try controller.writeScreenshot(to: url)

        let data = try Data(contentsOf: url)
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(data.count > 1024)
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func skyChangesWithTimeOfDay() throws {
        let day = try renderEnvironment(
            scene: RenderScene(instances: [], sky: SkyParameters()),
            timeOfDay: 13
        )
        let night = try renderEnvironment(
            scene: RenderScene(instances: [], sky: SkyParameters()),
            timeOfDay: 1
        )
        #expect(day.pixels.allSatisfy { $0 != 0 }, "day sky did not fill frame")
        let sample = ((day.height * 3 / 4) * day.width + day.width / 2) * 4
        let difference = (0 ..< 3).reduce(0) { total, channel in
            total + abs(Int(day.pixels[sample + channel]) - Int(night.pixels[sample + channel]))
        }
        #expect(difference > 40, "time-of-day parameter did not change sky")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func waterDrawsThroughBlendPipeline() throws {
        let device = try #require(Self.device)
        let mesh = try RenderMesh(device: device, mesh: WaterMeshBuilder.cellPlane())
        let bounds = ModelBounds(
            min: SIMD3(0, 0, 0),
            max: SIMD3(TerrainMeshBuilder.cellSize, TerrainMeshBuilder.cellSize, 0)
        )
        let water = WaterDrawItem(
            mesh: mesh,
            modelMatrix: matrix_identity_float4x4,
            shallowColor: SIMD3(0.85, 0.12, 0.05),
            deepColor: SIMD3(0.45, 0.04, 0.02),
            reflectionColor: SIMD3(0.9, 0.3, 0.1),
            bounds: bounds
        )
        let camera = SceneCamera.framing(bounds: (min: bounds.min, max: bounds.max))
        let clearUnderlay = try renderEnvironment(
            scene: RenderScene(instances: [], water: [water]),
            camera: camera,
            timeOfDay: 13
        )
        let skyUnderlay = try renderEnvironment(
            scene: RenderScene(instances: [], water: [water], sky: SkyParameters()),
            camera: camera,
            timeOfDay: 13
        )
        #expect(clearUnderlay.stats.drawCalls == 1)
        #expect(skyUnderlay.stats.drawCalls == 1)
        let center = ((skyUnderlay.height / 2) * skyUnderlay.width + skyUnderlay.width / 2) * 4
        let difference = (0 ..< 3).reduce(0) { total, channel in
            total + abs(
                Int(clearUnderlay.pixels[center + channel])
                    - Int(skyUnderlay.pixels[center + channel])
            )
        }
        #expect(difference > 10, "water did not blend with sky underlay")
    }

    @MainActor
    private func renderEnvironment(
        scene: RenderScene,
        camera: SceneCamera = .demo,
        timeOfDay: Float
    ) throws -> EnvironmentRender {
        let device = try #require(Self.device)
        let width = 320
        let height = 200
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: scene,
            camera: camera,
            timeOfDay: timeOfDay
        )
        let texture = try renderer.renderOffscreen(width: width, height: height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0
            )
        }
        return EnvironmentRender(
            pixels: pixels,
            width: width,
            height: height,
            stats: renderer.lastDrawStats
        )
    }
}
