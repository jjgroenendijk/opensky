// Mesh-shader grass against the classic grass draw on synthetic blades: the two paths must
// give the same frame, and the object stage must cull the meshlets outside the view.

import Metal
import MetalKit
import OpenSkyEngineTesting
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyRendering
import OpenSkyTagsTesting
@testable import OpenSkyWorld
import simd
import Testing

@Suite(.tags(.gpu))
@MainActor
struct RendererMeshGrassTests {
    private static let width = 320
    private static let height = 200
    /// Blades along +X, far past the right edge of the view.
    private static let blades = 300

    private static func stripMesh() -> Mesh {
        var positions: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt16] = []
        for blade in 0 ..< blades {
            let x = Float(blade) * 20
            let first = UInt16(positions.count)
            positions += [
                SIMD3(x - 8, 0, 0), SIMD3(x + 8, 0, 0), SIMD3(x + 8, 0, 80), SIMD3(x - 8, 0, 80)
            ]
            uvs += [SIMD2(0, 1), SIMD2(1, 1), SIMD2(1, 0), SIMD2(0, 0)]
            indices += [first, first + 1, first + 2, first, first + 2, first + 3]
        }
        return Mesh(
            name: "synthetic grass strip", transform: matrix_identity_float4x4,
            positions: positions,
            normals: [SIMD3<Float>](repeating: SIMD3(0, -1, 0), count: positions.count),
            tangents: [], bitangents: [], uvs: uvs, colors: [], indices: indices, materialSlot: 0
        )
    }

    private static func scene(device: MTLDevice) throws -> RenderScene {
        let material = Material(
            diffuseTexture: nil, normalTexture: nil, uvOffset: .zero, uvScale: SIMD2(repeating: 1),
            alpha: 1, glossiness: 0, specularColor: .zero, specularStrength: 0, doubleSided: true,
            alphaBlend: false, alphaTestThreshold: 0.5
        )
        let texture = try OffscreenRendererFixture.solidTexture(device: device)
        let source = Model(meshes: [stripMesh()], materials: [material], skippedShapeCount: 0)
        let model = try RenderModel(device: device, model: source) { _, _ in texture }
        let bounds = try #require(ModelBounds.containing(model: source))
        let placements = [-60, 0, 60].map { row in
            GrassRenderPlacement(
                placement: GrassPlacement(
                    grass: FormID(0x500), modelPath: "grass.nif",
                    position: SIMD3(-100, Float(row), 0),
                    normal: SIMD3(0, 0, 1), yawRadians: 0, scale: SIMD3(repeating: 1),
                    color: SIMD3(0.6, 0.8, 0.4), wavePeriod: 1, flags: []
                ),
                model: model, modelBounds: bounds
            )
        }
        return RenderScene(instances: [], grass: placements)
    }

    private static func makeRenderer() throws -> Renderer {
        let device = try #require(OffscreenRendererFixture.device)
        let camera = SceneCamera(
            eye: SIMD3(0, -500, 120), target: SIMD3(0, 0, 40),
            sunDirection: SceneCamera.demo.sunDirection, sunColor: SceneCamera.demo.sunColor,
            ambientColor: SIMD3(repeating: 1)
        )
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: width, height: height), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view, scene: scene(device: device), camera: camera,
            shaderLibrary: ShaderLibraryFixture.library(device: device)
        )
        renderer.shadowQuality = .off
        renderer.worldSimPaused = true
        return renderer
    }

    private static func frame(_ renderer: Renderer) throws -> TexturePixels {
        try TexturePixels(
            width: width, height: height,
            rgba: OffscreenRendererFixture.pixels(
                of: renderer.renderOffscreen(width: width, height: height)
            )
        )
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func theMeshPathDrawsTheClassicFrameAndCullsMeshlets() throws {
        let renderer = try Self.makeRenderer()
        try #require(renderer.meshShaderGrassUnavailableReason == nil)
        let classic = try Self.frame(renderer)
        #expect(renderer.lastGrassDrawStats.drawnInstances == 3)

        renderer.meshShaderGrassEnabled = true
        var mesh = try Self.frame(renderer)
        for _ in 0 ..< Renderer.maxFramesInFlight + 1 {
            mesh = try Self.frame(renderer)
        }
        #expect(renderer.drawsGrassWithMeshShaders)
        #expect(renderer.meshShaderGrassUnavailableReason == nil)
        let match = try TextureImageDifference.compare(
            reference: classic, candidate: mesh, normals: false
        ).rgbPSNR
        #expect(match > 45, "mesh path PSNR \(match) dB against the classic path")

        let counts = renderer.meshGrass.lastCounts
        let perInstance = try #require(renderer.meshGrass.meshlets.values.first).count
        #expect(counts.meshes == 1)
        #expect(counts.tested == 3 * perInstance)
        #expect(counts.drawn > 0)
        #expect(counts.drawn < counts.tested / 2, "drawn \(counts.drawn) of \(counts.tested)")
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func aSceneSwapToNewGrassMeshesKeepsDrawing() throws {
        let device = try #require(OffscreenRendererFixture.device)
        let renderer = try Self.makeRenderer()
        renderer.meshShaderGrassEnabled = true
        for _ in 0 ..< 3 {
            _ = try Self.frame(renderer)
        }
        for _ in 0 ..< 3 {
            try renderer.setScene(Self.scene(device: device))
            for _ in 0 ..< 3 {
                _ = try Self.frame(renderer)
            }
        }
        #expect(renderer.meshGrass.meshlets.count == 1)
        #expect(renderer.meshGrass.lastCounts.drawn > 0)
    }

    @Test(.enabled(if: OffscreenRendererFixture.hasMetal4Device))
    func debugViewsKeepTheClassicPath() throws {
        let renderer = try Self.makeRenderer()
        renderer.meshShaderGrassEnabled = true
        renderer.renderDebug.mode = .wireframe
        renderer.renderDebugAppliesOffscreen = true
        _ = try Self.frame(renderer)
        #expect(!renderer.drawsGrassWithMeshShaders)
        #expect(renderer.meshGrass.meshlets.isEmpty)
    }
}
