// Offscreen renderer setup and pixel readback that the Metal-gated render
// suites share. Everything is built in code.

import Foundation
import Metal
import MetalKit
@testable import OpenSkyFormatsCore
@testable import OpenSkyRendering
import simd
import Testing

public enum OffscreenRendererFixture {
    /// A Metal 4 device, or nil on a GPU that cannot run the renderer.
    public static let device: MTLDevice? = {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            device.supportsFamily(.metal4) else { return nil }
        return device
    }()

    public static var hasMetal4Device: Bool {
        device != nil
    }

    /// A paused view, so only `renderOffscreen` draws.
    @MainActor
    public static func pausedView(device: MTLDevice, width: Int, height: Int) -> MTKView {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: width, height: height), device: device)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        return view
    }

    /// A renderer with no frame driver over a paused view. `shaderLibrary` nil loads
    /// the app bundle's shaders.
    @MainActor
    public static func makeRenderer(
        device: MTLDevice,
        width: Int,
        height: Int,
        scene: RenderScene? = nil,
        camera: SceneCamera? = nil,
        shaderLibrary: MTLLibrary?
    ) throws -> Renderer {
        try Renderer(
            rendering: pausedView(device: device, width: width, height: height),
            scene: scene, camera: camera, shaderLibrary: shaderLibrary
        )
    }

    /// One frame at a fixed animation time, read back as BGRA8 bytes.
    @MainActor
    public static func render(
        _ renderer: Renderer,
        width: Int,
        height: Int,
        animationTime: Float = 1
    ) throws -> [UInt8] {
        try pixels(of: renderer.renderOffscreen(
            width: width, height: height, animationTime: animationTime
        ))
    }

    /// The texture's BGRA8 bytes, row after row.
    public static func pixels(of texture: MTLTexture) -> [UInt8] {
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

    /// Pixels where any colour channel moved by more than `tolerance`. The
    /// alpha byte is ignored.
    public static func changedPixels(_ lhs: [UInt8], _ rhs: [UInt8], tolerance: Int = 8) -> Int {
        stride(from: 0, to: min(lhs.count, rhs.count), by: 4).count { index in
            (0 ..< 3).contains { abs(Int(lhs[index + $0]) - Int(rhs[index + $0])) > tolerance }
        }
    }

    /// Pixels that are not the pure black clear colour.
    public static func litPixelCount(_ pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).count { !isBlack(pixels, offset: $0) }
    }

    /// True when the pixel at `point` is the pure black clear colour.
    public static func isBackground(
        _ pixels: [UInt8],
        at point: (x: Int, y: Int),
        width: Int
    ) -> Bool {
        isBlack(pixels, offset: (point.y * width + point.x) * 4)
    }

    /// Projects a world point through the view and projection that an
    /// offscreen render of `camera` uses. Nil when it lands off screen.
    public static func project(
        _ world: SIMD3<Float>,
        camera: SceneCamera,
        width: Int,
        height: Int
    ) -> (x: Int, y: Int)? {
        let viewMatrix = FreeFlyCamera(framing: camera).viewMatrix()
        let projection = MatrixMath.perspective(
            fovYRadians: MatrixMath.radians(fromDegrees: 65),
            aspectRatio: Float(width) / Float(height),
            nearZ: Renderer.nearPlane,
            farZ: Renderer.farPlane
        )
        let clip = projection * viewMatrix * SIMD4(world, 1)
        guard clip.w > 0 else { return nil }
        let ndc = SIMD3(clip.x, clip.y, clip.z) / clip.w
        guard abs(ndc.x) < 1, abs(ndc.y) < 1 else { return nil }
        return (Int((ndc.x + 1) / 2 * Float(width)), Int((1 - ndc.y) / 2 * Float(height)))
    }

    private static func isBlack(_ pixels: [UInt8], offset: Int) -> Bool {
        pixels[offset] == 0 && pixels[offset + 1] == 0 && pixels[offset + 2] == 0
    }

    /// A 2x2 light-grey texture, so a lit mesh shows its shading only.
    public static func solidTexture(device: MTLDevice) throws -> MTLTexture {
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
}

/// A frame size and shader source, so a suite builds and renders a demo-scene
/// renderer in one call each.
public struct OffscreenCanvas: Sendable {
    public enum Shaders: Sendable {
        /// The app bundle's `default.metallib`, for app-hosted suites.
        case appBundle
        /// `ShaderLibraryFixture`, for package suites.
        case packageFixture
    }

    public let width: Int
    public let height: Int
    public let shaders: Shaders

    public init(width: Int, height: Int, shaders: Shaders) {
        self.width = width
        self.height = height
        self.shaders = shaders
    }

    /// The device and the shaders this canvas renders with.
    @MainActor
    public func resources() throws -> (device: MTLDevice, library: MTLLibrary?) {
        let device = try #require(OffscreenRendererFixture.device)
        let library = switch shaders {
        case .appBundle: nil as MTLLibrary?
        case .packageFixture: try ShaderLibraryFixture.library(device: device)
        }
        return (device, library)
    }

    @MainActor
    public func makeRenderer() throws -> Renderer {
        let (device, library) = try resources()
        return try OffscreenRendererFixture.makeRenderer(
            device: device, width: width, height: height, shaderLibrary: library
        )
    }

    @MainActor
    public func render(_ renderer: Renderer) throws -> [UInt8] {
        try OffscreenRendererFixture.render(renderer, width: width, height: height)
    }
}
