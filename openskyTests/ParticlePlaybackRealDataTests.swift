// M7.3.2 env-gated acceptance over user's read-only Skyrim SE install.
// Builds WhiterunWorld cell (4,-2), isolates its paired flame/smoke system,
// renders two exact simulation times, records numeric delta + PNG evidence.

import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
@testable import opensky
import Testing
import UniformTypeIdentifiers

struct ParticlePlaybackRealDataTests {
    private static let device: MTLDevice? = {
        guard let device = MTLCreateSystemDefaultDevice(), device.supportsFamily(.metal4)
        else { return nil }
        return device
    }()

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
    func flameAndSmokeAnimateInWhiterunOffscreenFrames() throws {
        let device = try #require(Self.device)
        let root = try #require(Self.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(file: file, meshes: meshes, textures: textures)
        let cell = try builder.buildScene(
            worldspaceEditorID: "WhiterunWorld", gridX: 4, gridY: -2
        )
        let paired = cell.renderScene.particles.filter {
            $0.sourcePath.hasSuffix("effects\\ambient\\fxsmokelargeclose01.nif")
        }
        let flame = try #require(paired.first { $0.name == "FlamesTall01" })
        let smoke = try #require(paired.first { $0.name == "smoke10" })
        #expect(flame.blendMode == .additive)
        #expect(smoke.blendMode == .alpha)

        let particles = [flame, smoke]
        let firstTime: Float = 0.75
        let secondTime: Float = 1.25
        for playback in particles {
            playback.seek(to: firstTime, wind: .calm, emissionScale: 1)
        }
        let bounds = try #require(particleBounds(particles))
        let camera = SceneCamera.framing(bounds: bounds)
        let scene = RenderScene(instances: [], particles: particles)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: 512, height: 512), device: device
        )
        view.isPaused = true
        let renderer = try Renderer(view: view, scene: scene, camera: camera)
        renderer.sunShadowsEnabled = false
        let first = try readPixels(renderer.renderOffscreen(
            width: 512, height: 512, animationTime: firstTime
        ))
        let second = try readPixels(renderer.renderOffscreen(
            width: 512, height: 512, animationTime: secondTime
        ))
        let firstLit = litPixelCount(first)
        let secondLit = litPixelCount(second)
        let changed = changedPixelCount(first, second)
        #expect(firstLit > 20, "Whiterun flame/smoke first frame is blank")
        #expect(secondLit > 20, "Whiterun flame/smoke second frame is blank")
        #expect(changed > 20, "Whiterun flame/smoke did not animate: \(changed) pixels")

        let firstURL = try writePNG(first, name: "particles-whiterun-a.png")
        let secondURL = try writePNG(second, name: "particles-whiterun-b.png")
        let evidence = """
        [INFO] WhiterunWorld (4,-2) particle acceptance
        [INFO] flame: \(flame.sourcePath) / \(flame.name), blend=additive
        [INFO] smoke: \(smoke.sourcePath) / \(smoke.name), blend=alpha
        [INFO] exact times: \(firstTime)s -> \(secondTime)s
        [INFO] lit pixels: \(firstLit) -> \(secondLit); changed pixels: \(changed)
        [INFO] frames: \(firstURL.path), \(secondURL.path)
        """
        try evidence.write(
            to: logsDirectory.appending(path: "particle-acceptance.log"),
            atomically: true,
            encoding: .utf8
        )
        print(evidence)
    }

    private func particleBounds(
        _ playbacks: [ParticlePlayback]
    ) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        var lower = SIMD3<Float>(repeating: .greatestFiniteMagnitude)
        var upper = SIMD3<Float>(repeating: -.greatestFiniteMagnitude)
        var found = false
        for playback in playbacks {
            for particle in playback.simulator.particles {
                let extent = SIMD3<Float>(repeating: particle.radius)
                lower = min(lower, particle.position - extent)
                upper = max(upper, particle.position + extent)
                found = true
            }
        }
        return found ? (lower, upper) : nil
    }

    @MainActor
    private func readPixels(_ texture: MTLTexture) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: texture.width * texture.height * 4)
        result.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base,
                bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0
            )
        }
        return result
    }

    private func litPixelCount(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).reduce(into: 0) { count, index in
            if pixels[index] > 8 || pixels[index + 1] > 8 || pixels[index + 2] > 8 {
                count += 1
            }
        }
    }

    private func changedPixelCount(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).reduce(into: 0) { count, index in
            let delta = abs(Int(lhs[index]) - Int(rhs[index]))
                + abs(Int(lhs[index + 1]) - Int(rhs[index + 1]))
                + abs(Int(lhs[index + 2]) - Int(rhs[index + 2]))
            if delta > 24 {
                count += 1
            }
        }
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "logs")
    }

    private func writePNG(_ pixels: [UInt8], name: String) throws -> URL {
        var data = pixels
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &data,
            width: 512,
            height: 512,
            bitsPerComponent: 8,
            bytesPerRow: 512 * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ))
        let image = try #require(context.makeImage())
        try FileManager.default.createDirectory(
            at: logsDirectory, withIntermediateDirectories: true
        )
        let url = logsDirectory.appending(path: name)
        let destination = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }
}
