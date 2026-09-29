// A synthetic ground and tower under a low sun, shared by the sun-shadow suites
// and the acceptance chains that render it. Everything is built in code.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import RenderingTesting
import simd

public enum ShadowSceneFixtureError: Error {
    case textureAllocationFailed
    case emptyModel
}

public enum ShadowSceneFixture {
    public static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    public static var hasMetal4Device: Bool {
        device != nil
    }

    public static let width = 320
    public static let height = 240

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

    @MainActor
    public static func makeRenderer(
        device: MTLDevice,
        scene: RenderScene? = nil
    ) throws -> Renderer {
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height),
            device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return try Renderer(
            view: view,
            scene: scene ?? shadowScene(device: device),
            camera: camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
    }

    /// Ground + a near tower + a second tower far past shadowDistance on +X.
    /// The two towers share one RenderModel -> one DrawGroup with two
    /// instances, so per-cascade culling must keep the near instance and drop
    /// the far one from every cascade.
    public static func cullingScene(device: MTLDevice) throws -> RenderScene {
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
        let groundBounds = try bounds(of: groundModel)
        let towerBounds = try bounds(of: towerModel)
        let identity = matrix_identity_float4x4
        let far = MatrixMath.translation(SIMD3<Float>(200_000, 0, 0))
        return RenderScene(
            instances: [
                RenderPlacement(
                    model: ground, transform: identity,
                    bounds: groundBounds.transformed(by: identity)
                ),
                RenderPlacement(
                    model: tower, transform: identity,
                    bounds: towerBounds.transformed(by: identity)
                ),
                RenderPlacement(
                    model: tower, transform: far,
                    bounds: towerBounds.transformed(by: far)
                )
            ],
            sky: SkyParameters()
        )
    }

    /// Count of pixels the shadowed render darkened past a small threshold.
    public static func darkerPixelCount(on: [UInt8], off: [UInt8]) -> Int {
        var darker = 0
        for pixel in stride(from: 0, to: on.count, by: 4) {
            var delta = 0
            for channel in 0 ..< 3 {
                delta += Int(off[pixel + channel]) - Int(on[pixel + channel])
            }
            if delta > 40 {
                darker += 1
            }
        }
        return darker
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
        let groundBounds = try bounds(of: groundModel)
        let towerBounds = try bounds(of: towerModel)
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
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw ShadowSceneFixtureError.textureAllocationFailed
        }
        let bytes = [UInt8](repeating: 200, count: 2 * 2 * 4)
        texture.replace(
            region: MTLRegionMake2D(0, 0, 2, 2),
            mipmapLevel: 0,
            withBytes: bytes,
            bytesPerRow: 2 * 4
        )
        return texture
    }

    public static func readPixels(texture: MTLTexture) -> [UInt8] {
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

    private static func bounds(of model: Model) throws -> ModelBounds {
        guard let bounds = ModelBounds.containing(model: model) else {
            throw ShadowSceneFixtureError.emptyModel
        }
        return bounds
    }
}
