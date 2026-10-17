// Renders a `PreviewScene` once per camera view through the game's renderer, and
// measures each frame, so a frame that drew nothing fails instead of passing blank.
// Pipeline: docs/tools/preview-render.md.

import Foundation
import Metal
import MetalKit
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRendering
import OpenSkyWorld
import simd

/// One rendered view and what it drew.
public struct PreviewFrame {
    public let measure: PreviewViewMeasure
    public let camera: SceneCamera
    public let texture: any MTLTexture
}

/// The parts of a preview render that come from the install.
public struct PreviewRenderSources {
    public let device: any MTLDevice
    /// Weather and climate records for the cell stage.
    public let loadOrder: LoadOrderPlugins
    /// Cloud textures for the cell stage; nil draws no clouds.
    public let fileSystem: (any GameFileSource)?
    public var shaderLibrary: (any MTLLibrary)?

    public init(
        device: any MTLDevice,
        loadOrder: LoadOrderPlugins,
        fileSystem: (any GameFileSource)?,
        shaderLibrary: (any MTLLibrary)? = nil
    ) {
        self.device = device
        self.loadOrder = loadOrder
        self.fileSystem = fileSystem
        self.shaderLibrary = shaderLibrary
    }
}

public enum PreviewRenderJob {
    /// Renders every view with one renderer. A blank view is returned, not thrown, so
    /// the report still shows it; `PreviewViewMeasure.isBlank` marks it.
    public static func render(
        _ scene: PreviewScene,
        request: PreviewRequest,
        sources: PreviewRenderSources,
        adjust: (Renderer) -> Void = { _ in }
    ) throws -> [PreviewFrame] {
        let size = (width: request.width, height: request.height)
        let view = MTKView(
            frame: CGRect(x: 0, y: 0, width: size.width, height: size.height),
            device: sources.device
        )
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        let first = camera(for: request.views[0], scene: scene)
        let renderer = try Renderer(
            view: view, scene: scene.renderScene, camera: first,
            timeOfDay: request.timeOfDay, shaderLibrary: sources.shaderLibrary
        )
        try configure(renderer, scene: scene, request: request, sources: sources)
        adjust(renderer)
        let triangles = triangleCount(scene.renderScene)
        return try request.views.map { previewView in
            let camera = camera(for: previewView, scene: scene)
            renderer.camera = camera
            renderer.freeFlyCamera = FreeFlyCamera(framing: camera)
            let texture = try renderer.renderOffscreen(
                width: size.width, height: size.height, animationTime: 0
            )
            let stats = renderer.combinedDrawStats(gpu: renderer.lastFrameGPUCullCounts())
            let measure = PreviewViewMeasure(
                view: previewView,
                distance: scene.entry == nil ? simd_distance(camera.eye, camera.target) : 0,
                drawCalls: stats.drawCalls, drawnInstances: stats.drawnInstances,
                triangles: triangles, coverage: coverage(of: texture)
            )
            return PreviewFrame(measure: measure, camera: camera, texture: texture)
        }
    }

    /// Orbits the focus box, or turns from the entry eye of an interior: the yaw
    /// turns away from the arrival heading, and the pitch looks down.
    public static func camera(for view: PreviewView, scene: PreviewScene) -> SceneCamera {
        if let entry = scene.entry {
            let turn = SIMD3<Float>(-view.pitch, 0, -view.yaw) * (.pi / 180)
            return SceneCamera.teleport(placement: PlacedReference.Placement(
                position: entry.position, rotation: SIMD3(0, 0, entry.rotation.z) + turn
            ))
        }
        return SceneCamera.framing(
            bounds: (scene.focus.min, scene.focus.max),
            from: view.eyeDirection,
            distance: view.distance
        )
    }

    private static func configure(
        _ renderer: Renderer,
        scene: PreviewScene,
        request: PreviewRequest,
        sources: PreviewRenderSources
    ) throws {
        if scene.stage == .studio {
            renderer.offscreenBackground = PreviewStudio.background
            renderer.sunShadowsEnabled = false
        }
        guard let worldspace = scene.weatherWorldspace else { return }
        guard
            let weather = WeatherSystem(
                loadOrder: sources.loadOrder, worldspaceEditorID: worldspace
            )
        else { return }
        renderer.weather = weather
        if let name = request.weather {
            guard let found = weather.store.weathers.values.first(where: { $0.editorID == name })
            else { throw PreviewError.notFound(name) }
            weather.forceWeather(found.formID, transition: .instant)
        }
        if let fileSystem = sources.fileSystem {
            renderer.skyClouds = try SkyClouds(
                fileSystem: fileSystem, device: sources.device, immediate: true
            )
        }
    }

    static func triangleCount(_ scene: RenderScene) -> Int {
        (scene.opaque + scene.alphaTested).reduce(0) { total, group in
            total + group.mesh.indexCount / 3 * group.instances.count
        }
    }

    /// Reads the frame back and counts the pixels that are not the most common colour.
    static func coverage(of texture: any MTLTexture) -> Double {
        var pixels = [UInt32](repeating: 0, count: texture.width * texture.height)
        pixels.withUnsafeMutableBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.getBytes(
                base, bytesPerRow: texture.width * 4,
                from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0
            )
        }
        return PreviewCoverage.fraction(pixels)
    }
}

/// How much of a frame is not background. Pure, so a test can feed it pixels.
nonisolated public enum PreviewCoverage {
    /// A channel difference at or below this counts as the same colour.
    static let tolerance = 8

    public static func fraction(_ pixels: [UInt32]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        var counts: [UInt32: Int] = [:]
        for pixel in pixels {
            counts[pixel, default: 0] += 1
        }
        guard let background = counts.max(by: { $0.value < $1.value })?.key else { return 0 }
        let differing = pixels.lazy.filter { !same($0, background) }.count
        return Double(differing) / Double(pixels.count)
    }

    private static func same(_ first: UInt32, _ second: UInt32) -> Bool {
        (0 ..< 3).allSatisfy { channel in
            let shift = UInt32(channel * 8)
            let left = Int((first >> shift) & 0xFF)
            let right = Int((second >> shift) & 0xFF)
            return abs(left - right) <= tolerance
        }
    }
}
