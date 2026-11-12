// A renderer port that draws nothing and records what menus and adapters ask of it,
// so their code runs on a runner without Metal 4.

public import Foundation
public import Metal
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyFormatsSWF
public import OpenSkyRenderCore
public import OpenSkyRendering
public import simd

@MainActor
public final class FakeRendererPort: RendererPort {
    /// The arguments of one `setLoadingCover` call.
    public struct LoadingCover {
        public let placements: [RenderPlacement]?
        public let particleCount: Int
        public let hasLighting: Bool
    }

    public enum FakeError: Error {
        case noOffscreenFrames
    }

    public let device: any MTLDevice
    public var skyCelestial: SkyCelestial?
    public var skyClouds: SkyClouds?
    public var swfScale: Float = 1
    public var swfMainMovieHidden = false
    public var swfGamepadCount = 0
    public var swfSoundPlayer: (@MainActor (String?) -> Void)?
    public var animationTime: Float = 0
    public var areFirstPersonArmsVisible = false
    private static let startCamera = SceneCamera(
        eye: .zero, target: SIMD3(0, 1, 0), sunDirection: SceneCamera.defaultSunDirection,
        sunColor: SceneCamera.defaultSunColor, ambientColor: SceneCamera.defaultAmbientColor
    )

    public var camera = FakeRendererPort.startCamera
    public var detectionOverlayEnabled = false
    public var drawableAspectRatio: Float = 1
    public var navmeshOverlayEnabled = false
    public var pathOverlayEnabled = false
    public var pointShadowLightCount = 0
    public var projectionMatrix = matrix_identity_float4x4
    public var renderDebug = RenderDebugState.production
    public var scene = RenderScene(instances: [])
    public var shadowQuality = ShadowQuality.off
    public var swfEnabled = true
    public var swfOpacity: Float = 1
    public var swfRuntime: SWFMovieRuntime?
    public var transientPointLights: [RenderPointLight] = []
    public var uiEnabled = true
    public var frameInput =
        RenderFrameInput(view: FreeFlyCamera(framing: FakeRendererPort.startCamera))
    public var waterRipples = WaterRippleField()

    /// What `startMenuMovie` answers; false is a movie that would not start.
    public var startsMenuMovies = false
    public private(set) var menuMovieStarts = 0
    public private(set) var hadMenuMoviePreparation: [Bool] = []
    public private(set) var swfInputs: [SWFInputEvent] = []
    public private(set) var swfOverlays: [SWFMovieScene?] = []
    public private(set) var swfRuntimeLimits: [AS2Limits] = []
    public private(set) var moviePictures: [(picture: MoviePicture?, letterbox: Bool)] = []
    public private(set) var loadingCovers: [LoadingCover] = []
    public private(set) var menuScenes: [MenuScene?] = []
    public private(set) var overlayUpdates = 0
    public private(set) var replacedImages: [String] = []

    /// Nil when the machine has no Metal device at all.
    public init?() {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.device = device
    }

    public func advanceSWFRuntime() throws {}

    public func sendSWFInput(_ event: SWFInputEvent) throws -> Bool {
        swfInputs.append(event)
        return swfRuntime != nil
    }

    public func startMenuMovie(
        _: SWFMovieScene, prepare: ((SWFMovieRuntime) -> Void)?
    ) throws -> Bool {
        menuMovieStarts += 1
        hadMenuMoviePreparation.append(prepare != nil)
        return startsMenuMovies
    }

    public func setSWFOverlay(
        _ scene: SWFMovieScene?, prepare _: ((SWFMovieRuntime) -> Void)?
    ) throws -> SWFMovieRuntime? {
        swfOverlays.append(scene)
        return nil
    }

    public func advanceSWFOverlay() throws {}

    public func setSWFMovie(_: SWFMovieScene?) throws {}

    public func startSWFRuntime(
        limits: AS2Limits, prepare _: ((SWFMovieRuntime) -> Void)?
    ) throws -> SWFMovieRuntime? {
        swfRuntimeLimits.append(limits)
        return swfRuntime
    }

    public func replaceSWFImage(_ name: String, rgba _: Data, width _: Int, height _: Int) -> Bool {
        replacedImages.append(name)
        return false
    }

    public func addWaterRipple(at _: SIMD3<Float>, strength _: Float) {}

    public func renderOffscreen(width _: Int, height _: Int) throws -> any MTLTexture {
        throw FakeError.noOffscreenFrames
    }

    public func setLoadingCover(
        _ placements: [RenderPlacement]?,
        particles: [ParticlePlayback],
        lighting: RenderLighting?
    ) throws {
        loadingCovers.append(LoadingCover(
            placements: placements, particleCount: particles.count, hasLighting: lighting != nil
        ))
    }

    public func setMenuScene(_ scene: MenuScene?) {
        menuScenes.append(scene)
    }

    public func setMoviePicture(_ picture: MoviePicture?, letterbox: Bool) {
        moviePictures.append((picture, letterbox))
    }

    public func updateSWFOverlay(_: (SWFMovieRuntime) -> Void) throws {
        overlayUpdates += 1
    }

    public func updateSWFRuntime(_ body: (SWFMovieRuntime) -> Void) throws {
        swfRuntime.map(body)
    }

    public func updateWaders(_: [(key: ReferenceKey, position: SIMD3<Float>)]) {}
}
