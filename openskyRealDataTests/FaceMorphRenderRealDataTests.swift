// Env-gated M17.6 acceptance over the user's read-only install. Associates
// Heimskr's baked FaceGen shapes with HDPT expression TRIs, renders Aah at
// zero and one, and proves a repeated one-weight frame is deterministic.

import CoreGraphics
import Foundation
import Metal
import MetalKit
@testable import opensky
import simd
import Testing

struct FaceMorphRenderRealDataTests {
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty else {
            return nil
        }
        return try? GameDataLocator.locate()
    }()

    private static var canRun: Bool {
        device != nil && dataRoot != nil
    }

    @Test(.enabled(if: Self.canRun))
    @MainActor
    func expressionWeightChangesPixelsAndRepeatsDeterministically() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let vfs = VirtualFileSystem(root: root)
        let textures = TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: vfs
        )
        let placed = try PlacedActor(record: #require(
            ESMWalk.record(withFormID: 0x0001_A682, in: file)
        ))
        let resolvers = builder.actorResolversBuildingIfNeeded(localized: true)
        let appearance = try resolvers.template.resolve(base: placed.base)
        let visual = try resolvers.visual.resolve(appearance: appearance)
        let assembly = ActorAssembler(provider: meshes).assemble(placed: placed, visual: visual)
        let playback = try #require(builder.makeFaceMorphPlayback(assembly: assembly))

        try #require(
            playback.bindings.count >= 2,
            "Face morph association misses: \(playback.misses)"
        )
        try #require(playback.targetNames.contains("Aah"))
        #expect(playback.pairedPaths.contains {
            $0.lowercased().hasSuffix("malehead.tri")
        })
        #expect(playback.pairedPaths.contains {
            $0.lowercased().hasSuffix("mouthhuman.tri")
        })

        let scene = RenderScene(
            instances: assembly.renderPlacements(
                at: assembly.transform, faceMorphs: playback.bindings
            ),
            animations: [playback]
        )
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: 800, height: 800), device: device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let renderer = try Renderer(
            view: view,
            scene: scene,
            camera: faceCamera(assembly: assembly)
        )

        let baseline = try frame(renderer, name: "face-morph-zero.png")
        #expect(playback.setWeight(1, for: "Aah"))
        let morphed = try frame(renderer, name: "face-morph-aah.png")
        let repeated = try frame(renderer, name: nil)
        let delta = changedPixels(baseline, morphed)

        #expect(delta > 20, "Aah changed only \(delta) pixels")
        #expect(changedPixels(morphed, repeated) == 0)
        print(
            "[INFO] Face morph A/B: \(playback.bindings.count) pairs, "
                + "\(playback.targetNames.count) targets, \(delta) changed pixels"
        )
    }

    private func faceCamera(
        assembly: ActorAssembly<ActorRenderAsset>
    ) -> SceneCamera {
        let origin = SIMD3(
            assembly.transform.columns.3.x,
            assembly.transform.columns.3.y,
            assembly.transform.columns.3.z
        )
        let head = origin + SIMD3(0, 0, 112)
        let direction = simd_normalize(SIMD3<Float>(-1, -1, 0.25))
        return SceneCamera(
            eye: head + direction * 160,
            target: head,
            sunDirection: SceneCamera.demo.sunDirection,
            sunColor: SceneCamera.demo.sunColor,
            ambientColor: SceneCamera.demo.ambientColor
        )
    }

    @MainActor
    private func frame(_ renderer: Renderer, name: String?) throws -> [UInt8] {
        let texture = try renderer.renderOffscreen(width: 800, height: 800, animationTime: 0)
        if let name {
            try FrameScreenshot.write(
                texture: texture,
                to: runDirectory.appending(path: name)
            )
        }
        var pixels = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return pixels
    }

    private var runDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs/test-fast/latest")
    }

    private func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        guard lhs.count == rhs.count else { return max(lhs.count, rhs.count) / 4 }
        return stride(from: 0, to: lhs.count, by: 4).count { index in
            lhs[index ..< index + 4] != rhs[index ..< index + 4]
        }
    }
}
