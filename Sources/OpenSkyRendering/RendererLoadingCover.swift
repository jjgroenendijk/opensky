// The loading screen's 3D object. While a cover is set, the scene pass draws
// only the `.loadingCover` layer, its own particle systems, and the
// screen-space layers, so the world behind it never shows. See
// docs/engine/loading-screens.md.

import Metal
import OpenSkyRenderCore

extension Renderer {
    /// Shows `placements` and `particles` in place of the world, or the world again
    /// for nil. An empty list is a dark screen with only the overlay.
    public func setLoadingCover(
        _ placements: [RenderPlacement]?, particles: [ParticlePlayback] = []
    ) throws {
        let next = placements.map { RenderScene(instances: $0, particles: particles) }
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

    /// The cover's systems while a cover shows, else the world's and the effects'.
    var activeParticles: [ParticlePlayback] {
        effects.loadingCover?.particles ?? scene.particles + effects.particles
    }

    /// The layer the active particle systems draw under.
    var activeParticleLayer: RenderLayer {
        effects.loadingCover == nil ? .particles : .loadingCover
    }

    /// The cover's systems run on wall time, because the menu over them pauses the world.
    public func advanceLoadingCoverParticles(deltaTime: Float) {
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
