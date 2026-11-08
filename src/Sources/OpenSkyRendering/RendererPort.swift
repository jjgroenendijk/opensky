public import Foundation
@preconcurrency @unsafe public import Metal
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyFormatsSWF
public import OpenSkyRenderCore
public import simd

/// What the world adapters and the menus use of `Renderer`.
public protocol RendererPort: AnyObject {
    var skyCelestial: SkyCelestial? { get }
    func advanceSWFRuntime() throws
    @discardableResult func sendSWFInput(_ event: SWFInputEvent) throws -> Bool
    func startMenuMovie(
        _ scene: SWFMovieScene,
        prepare: ((SWFMovieRuntime) -> Void)?
    ) throws -> Bool
    @discardableResult func setSWFOverlay(
        _ scene: SWFMovieScene?, prepare: ((SWFMovieRuntime) -> Void)?
    ) throws -> SWFMovieRuntime?
    func advanceSWFOverlay() throws
    func setSWFMovie(_ scene: SWFMovieScene?) throws
    @discardableResult func startSWFRuntime(
        limits: AS2Limits, prepare: ((SWFMovieRuntime) -> Void)?
    ) throws -> SWFMovieRuntime?
    @discardableResult func replaceSWFImage(
        _ name: String,
        rgba: Data,
        width: Int,
        height: Int
    ) -> Bool
    var swfScale: Float { get set }
    var swfMainMovieHidden: Bool { get set }
    var swfGamepadCount: Int { get set }
    var swfSoundPlayer: (@MainActor (String?) -> Void)? { get set }
    func addWaterRipple(at position: SIMD3<Float>, strength: Float)
    var animationTime: Float { get }
    var areFirstPersonArmsVisible: Bool { get }
    var camera: SceneCamera { get set }
    var detectionOverlayEnabled: Bool { get set }
    var device: any MTLDevice { get }
    var drawableAspectRatio: Float { get }
    var navmeshOverlayEnabled: Bool { get set }
    var pathOverlayEnabled: Bool { get set }
    var pointShadowLightCount: Int { get }
    var projectionMatrix: float4x4 { get set }
    var renderDebug: RenderDebugState { get set }
    func renderOffscreen(width: Int, height: Int) throws -> any MTLTexture
    var scene: RenderScene { get set }
    func setLoadingCover(
        _ placements: [RenderPlacement]?,
        particles: [ParticlePlayback],
        lighting: RenderLighting?
    ) throws
    func setMenuScene(_ scene: MenuScene?)
    func setMoviePicture(_ picture: MoviePicture?, letterbox: Bool)
    var shadowQuality: ShadowQuality { get set }
    var swfEnabled: Bool { get set }
    var swfOpacity: Float { get set }
    var swfRuntime: SWFMovieRuntime? { get }
    var transientPointLights: [RenderPointLight] { get set }
    var uiEnabled: Bool { get set }
    func updateSWFOverlay(_ body: (SWFMovieRuntime) -> Void) throws
    func updateSWFRuntime(_ body: (SWFMovieRuntime) -> Void) throws
    func updateWaders(_ waders: [(key: ReferenceKey, position: SIMD3<Float>)])
    var frameInput: RenderFrameInput { get set }
    var waterRipples: WaterRippleField { get set }
}

/// The default arguments a protocol requirement cannot carry.
extension RendererPort {
    @discardableResult public func setSWFOverlay(_ scene: SWFMovieScene?) throws
        -> SWFMovieRuntime?
    {
        try setSWFOverlay(scene, prepare: nil)
    }

    public func startMenuMovie(_ scene: SWFMovieScene) throws -> Bool {
        try startMenuMovie(scene, prepare: nil)
    }

    @discardableResult public func startSWFRuntime(
        prepare: ((SWFMovieRuntime) -> Void)? = nil
    ) throws -> SWFMovieRuntime? {
        try startSWFRuntime(limits: .standard, prepare: prepare)
    }

    public func setMoviePicture(_ picture: MoviePicture?) {
        setMoviePicture(picture, letterbox: true)
    }

    public func setLoadingCover(
        _ placements: [RenderPlacement]?,
        lighting: RenderLighting?
    ) throws {
        try setLoadingCover(placements, particles: [], lighting: lighting)
    }

    public func setLoadingCover(
        _ placements: [RenderPlacement]?,
        particles: [ParticlePlayback]
    ) throws {
        try setLoadingCover(placements, particles: particles, lighting: nil)
    }

    public func setLoadingCover(_ placements: [RenderPlacement]?) throws {
        try setLoadingCover(placements, particles: [], lighting: nil)
    }
}

extension Renderer: RendererPort {}
