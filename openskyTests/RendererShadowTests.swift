// Cascaded sun-shadow renderer integration (M7.1.1): offscreen A/B renders of
// a synthetic ground + caster scene, deterministic pixel checks (AGENTS.md
// testing rule). Proves the depth pre-pass + PCF sampling actually darkens the
// receiver under a caster, only ever darkens (monotonic), and leaves the sky
// untouched — and that disabling shadows reproduces a never-enabled baseline.
// Skips without a Metal 4 device (paravirtual CI), pattern from
// RendererCullingTests / RendererOffscreenTests.

import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct RendererShadowTests {
    private static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    private static var hasMetal4Device: Bool {
        device != nil
    }

    private static let width = 320
    private static let height = 240

    /// Sun high in the west, travelling east + down: a tall thin tower at the
    /// origin throws a long shadow streak east across the flat ground.
    private static let sun = simd_normalize(SIMD3<Float>(0.8, 0, -0.6))

    /// Above + south-east of the origin, looking down the shadow streak so the
    /// tower does not occlude it and the sky fills the top of the frame.
    private static let camera = SceneCamera(
        eye: SIMD3(360, -720, 760),
        target: SIMD3(260, 0, 0),
        sunDirection: sun,
        sunColor: SIMD3(1, 1, 1),
        ambientColor: SIMD3(0.25, 0.25, 0.28)
    )

    // MARK: - Tests

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func shadowsDarkenReceiverUnderCasterAndSpareSky() throws {
        let device = try #require(Self.device)
        let renderer = try Self.makeRenderer(device: device)

        renderer.sunShadowsEnabled = true
        let onTexture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let on = Self.readPixels(texture: onTexture)

        renderer.sunShadowsEnabled = false
        let offTexture = try renderer.renderOffscreen(width: Self.width, height: Self.height)
        let off = Self.readPixels(texture: offTexture)

        // Shadows only ever remove the direct sun term: no channel may be
        // brighter with shadows on (allow 1 LSB of rounding).
        var brighter = 0
        var darkerPixels = 0
        for pixel in stride(from: 0, to: on.count, by: 4) {
            var pixelDarker = 0
            for channel in 0 ..< 3 {
                let onValue = Int(on[pixel + channel])
                let offValue = Int(off[pixel + channel])
                if onValue > offValue + 1 {
                    brighter += 1
                }
                pixelDarker += offValue - onValue
            }
            if pixelDarker > 40 {
                darkerPixels += 1
            }
        }
        #expect(brighter == 0, "shadows brightened \(brighter) channels — sun term math wrong")
        #expect(
            darkerPixels > 50,
            "only \(darkerPixels) pixels darkened — caster cast no visible shadow"
        )

        // The procedural sky ignores shadows entirely: the top band must be
        // bit-identical between the two renders.
        let topBand = Self.width * 6 * 4
        var skyDifferences = 0
        for index in 0 ..< topBand where on[index] != off[index] {
            skyDifferences += 1
        }
        #expect(skyDifferences == 0, "sky band changed with shadows — non-receiver was shaded")
    }

    @Test(.enabled(if: Self.hasMetal4Device))
    @MainActor
    func disabledShadowsMatchNeverEnabledBaseline() throws {
        let device = try #require(Self.device)

        // Enable shadows (populates the shadow map), then disable and render.
        let toggled = try Self.makeRenderer(device: device)
        toggled.sunShadowsEnabled = true
        _ = try toggled.renderOffscreen(width: Self.width, height: Self.height)
        toggled.sunShadowsEnabled = false
        let afterToggle = try Self.readPixels(
            texture: toggled.renderOffscreen(width: Self.width, height: Self.height)
        )

        // A renderer that never enabled shadows, matched frame count.
        let baseline = try Self.makeRenderer(device: device)
        baseline.sunShadowsEnabled = false
        _ = try baseline.renderOffscreen(width: Self.width, height: Self.height)
        let never = try Self.readPixels(
            texture: baseline.renderOffscreen(width: Self.width, height: Self.height)
        )

        var differences = 0
        for index in afterToggle.indices where afterToggle[index] != never[index] {
            differences += 1
        }
        #expect(differences == 0, "disabling shadows left \(differences) stale pixels")
    }

    // MARK: - Helpers

    @MainActor
    private static func makeRenderer(device: MTLDevice) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(
            view: view,
            scene: shadowScene(device: device),
            camera: camera
        )
    }

    /// Flat ground quad + a tall thin tower caster at the origin, under a sky.
    private static func shadowScene(device: MTLDevice) throws -> RenderScene {
        let texture = try solidTexture(device: device)
        let provider: TextureProvider = { _, _ in texture }

        let groundModel = Model(
            meshes: [DemoScene.planeMesh(halfSize: 1500, uvRepeat: 1)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let towerModel = Model(
            meshes: [DemoScene.boxMesh(halfWidth: 45, halfDepth: 45, height: 420)],
            materials: [Material.fallback],
            skippedShapeCount: 0
        )
        let ground = try RenderModel(device: device, model: groundModel, textureProvider: provider)
        let tower = try RenderModel(device: device, model: towerModel, textureProvider: provider)
        let groundBounds = try #require(ModelBounds.containing(model: groundModel))
        let towerBounds = try #require(ModelBounds.containing(model: towerModel))
        let identity = matrix_identity_float4x4
        return RenderScene(
            instances: [
                RenderPlacement(
                    model: ground,
                    transform: identity,
                    bounds: groundBounds.transformed(by: identity)
                ),
                RenderPlacement(
                    model: tower,
                    transform: identity,
                    bounds: towerBounds.transformed(by: identity)
                )
            ],
            sky: SkyParameters()
        )
    }

    private static func solidTexture(device: MTLDevice) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.pixelFormat = .rgba8Unorm_srgb
        descriptor.width = 2
        descriptor.height = 2
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        let bytes = [UInt8](repeating: 200, count: 2 * 2 * 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: 2 * 4
        )
        return texture
    }

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
}
