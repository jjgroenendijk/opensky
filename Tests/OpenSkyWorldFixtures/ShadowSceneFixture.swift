// A synthetic ground and tower under a low sun, shared by the sun-shadow suites
// and the acceptance chains that render it. Everything is built in code.

import Foundation
import Metal
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import RenderingTesting
import simd

public enum ShadowSceneFixtureError: Error {
    case emptyModel
}

public enum ShadowSceneFixture {
    public static let device = OffscreenRendererFixture.device
    public static let hasMetal4Device = OffscreenRendererFixture.hasMetal4Device

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
        try OffscreenRendererFixture.makeSessionRenderer(
            device: device,
            width: width,
            height: height,
            scene: scene ?? towerScene(device: device, towerOffsets: [.zero]),
            camera: camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
    }

    /// A second tower stands far past `shadowDistance` on +X. Both towers share
    /// one `RenderModel`, so one `DrawGroup` has two instances, and cascade
    /// culling must keep the near one and drop the far one.
    public static func cullingScene(device: MTLDevice) throws -> RenderScene {
        try towerScene(device: device, towerOffsets: [.zero, SIMD3(200_000, 0, 0)])
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

    /// Flat ground under a sky, with one tall thin tower at each offset.
    private static func towerScene(
        device: MTLDevice,
        towerOffsets: [SIMD3<Float>]
    ) throws -> RenderScene {
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
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
        let towers = towerOffsets.map { offset in
            let transform = MatrixMath.translation(offset)
            return RenderPlacement(
                model: tower, transform: transform, bounds: towerBounds.transformed(by: transform)
            )
        }
        let groundPlacement = RenderPlacement(
            model: ground, transform: identity, bounds: groundBounds.transformed(by: identity)
        )
        return RenderScene(instances: [groundPlacement] + towers, sky: SkyParameters())
    }

    public static func readPixels(texture: MTLTexture) -> [UInt8] {
        OffscreenRendererFixture.pixels(of: texture)
    }

    private static func bounds(of model: Model) throws -> ModelBounds {
        guard let bounds = ModelBounds.containing(model: model) else {
            throw ShadowSceneFixtureError.emptyModel
        }
        return bounds
    }
}
