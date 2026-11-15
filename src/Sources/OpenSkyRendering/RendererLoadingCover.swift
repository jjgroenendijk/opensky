// The loading screen's 3D object. While a cover is set, the scene pass draws
// only the `.loadingCover` layer, its own particle systems, and the
// screen-space layers, so the world behind it never shows. See
// docs/engine/loading-screens.md.

import Metal
public import OpenSkyRenderCore

/// A camera of the cover's own, which replaces the player's view while the cover shows.
nonisolated public struct LoadingCoverCamera: Sendable {
    public var view: FreeFlyCamera
    public var horizontalFieldOfView: Float

    public init(view: FreeFlyCamera, horizontalFieldOfView: Float) {
        self.view = view
        self.horizontalFieldOfView = horizontalFieldOfView
    }
}

/// Everything a cover draws in place of the world. With a camera, the cover is a scene
/// in its own space: only its own point lights light it and only its models cast.
public struct LoadingCoverScene {
    public var placements: [RenderPlacement]
    public var particles: [ParticlePlayback]
    public var pointLights: [RenderPointLight]
    public var lighting: RenderLighting?
    public var camera: LoadingCoverCamera?

    public init(
        placements: [RenderPlacement], particles: [ParticlePlayback] = [],
        pointLights: [RenderPointLight] = [], lighting: RenderLighting? = nil,
        camera: LoadingCoverCamera? = nil
    ) {
        self.placements = placements
        self.particles = particles
        self.pointLights = pointLights
        self.lighting = lighting
        self.camera = camera
    }
}

extension Renderer {
    /// Shows `placements` and `particles` in place of the world, or the world again
    /// for nil. An empty list is a dark screen with only the overlay. `lighting` is
    /// the cover's own light; without it the cover keeps the world's sun and ambient.
    public func setLoadingCover(
        _ placements: [RenderPlacement]?,
        particles: [ParticlePlayback] = [],
        lighting: RenderLighting? = nil
    ) throws {
        try setLoadingScene(placements.map {
            LoadingCoverScene(placements: $0, particles: particles, lighting: lighting)
        })
    }

    /// Shows `cover` in place of the world, or the world again for nil.
    public func setLoadingScene(_ cover: LoadingCoverScene?) throws {
        let next = cover.map {
            RenderScene(
                instances: $0.placements, lighting: $0.lighting, pointLights: $0.pointLights,
                particles: $0.particles
            )
        }
        effects.loadingCoverCamera = cover?.camera
        let retiring = effects.loadingCover?.residencyAllocations ?? []
        effects.loadingCover = next
        if let next {
            try growRings(
                drawCount: scene.drawCount + rigDrawCount + effects.scene.drawCount,
                instanceCount: scene.instanceCount + rigInstanceCount + effects.scene.instanceCount
            )
            let added = next.residencyAllocations
            if !added.isEmpty {
                residencySet.addAllocations(added)
                residencySet.commit()
            }
        }
        retireAllocations(retiring)
    }

    /// The cover's light while a cover with its own light shows, else the loaded cell's.
    var activeLighting: RenderLighting? {
        effects.loadingCover?.lighting ?? scene.lighting
    }

    /// The cover's lights while a cover shows, else the loaded scene's.
    var activePointLights: [RenderPointLight] {
        effects.loadingCover?.pointLights ?? scene.pointLights
    }

    /// The cover's camera replaces the player's view and field of view.
    func applyLoadingCoverCamera(to input: inout RenderFrameInput) {
        guard effects.loadingCover != nil, let camera = effects.loadingCoverCamera else { return }
        input.view = camera.view
        input.cameraPivot = nil
        input.horizontalFOVRadians = camera.horizontalFieldOfView
    }

    /// The cover's systems while a cover shows, else the world's and the effects'.
    var activeParticles: [ParticlePlayback] {
        effects.loadingCover?.particles ?? scene.particles + effects.particles
    }

    /// The layer the active particle systems draw under.
    var activeParticleLayer: RenderLayer {
        effects.loadingCover == nil ? .particles : .loadingCover
    }

    /// The cover's systems run on wall time, because the menu over them pauses the world.
    func advanceLoadingCoverParticles(deltaTime: Float) {
        guard particlesEnabled, !particlesFrozen, let cover = effects.loadingCover else { return }
        for playback in cover.particles {
            playback.advance(
                deltaTime: deltaTime, wind: .calm, emissionScale: particleEmissionScale
            )
        }
    }

    func advanceLoadingCoverParticlesFromWallClock() {
        let delta = effects.loadingCoverClock.advance(to: wallClock.now, paused: false)
        advanceLoadingCoverParticles(deltaTime: delta)
    }
}
