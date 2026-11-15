// Per-frame actor animation clock + measured palette refresh.

import Foundation
import OpenSkyGameData
import OpenSkyRenderCore
import simd

extension Renderer {
    public func updateAnimations(deltaTime: Float) {
        animationTime += max(deltaTime, 0)
        skyClouds?.drift.advance(
            seconds: deltaTime, velocities: frameInput.weather?.cloudVelocities ?? []
        )
        let started = DispatchTime.now().uptimeNanoseconds
        let sceneBones = if actorAnimationsEnabled {
            scene.updateAnimations(at: animationTime)
                + effects.scene.updateAnimations(at: animationTime)
        } else {
            scene.resetAnimationsToBindPose() + effects.scene.resetAnimationsToBindPose()
        }
        // The simulation steps the player's animation; this only publishes the pose and
        // honours the same A/B toggle (SkinnedPosePlayback.swift).
        lastAnimationUpdatedBoneCount = sceneBones
            + (frameInput.rigs.body?.publishAnimation(enabled: actorAnimationsEnabled) ?? 0)
            + (frameInput.rigs.arms?.publishAnimation(enabled: actorAnimationsEnabled) ?? 0)
        lastAnimationUpdateMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    @discardableResult
    func updateAnimationsFromWallClock() -> Float {
        // Returned delta also drives particles + precipitation this frame, so a
        // paused (zero) delta freezes all three together.
        let delta = animationClock
            .advance(to: wallClock.now, paused: frameInput.isPaused) * frameInput.timeScale
        updateAnimations(deltaTime: delta)
        return delta
    }

    func updateParticles(deltaTime: Float) {
        guard particlesEnabled, !particlesFrozen else { return }
        let playbacks = scene.particles + effects.particles
        particleBands.keep(playbacks)
        let viewer = frameInput.view.position
        for playback in playbacks {
            let placement = playback.simulator.placementTransform.columns.3
            guard
                let step = particleBands.step(
                    of: playback, at: SIMD3(placement.x, placement.y, placement.z),
                    viewer: viewer, deltaTime: deltaTime
                )
            else { continue }
            playback.advance(
                deltaTime: step,
                wind: frameInput.wind,
                emissionScale: particleEmissionScale
            )
        }
    }

    public func seekParticles(to time: Float) {
        guard particlesEnabled else { return }
        for playback in scene.particles {
            playback.seek(
                to: time,
                wind: frameInput.wind,
                emissionScale: particleEmissionScale
            )
        }
    }
}

extension Renderer {
    /// How many particle systems stepped in each band, by band name.
    public var particleBandCounts: [String: Int] {
        particleBands.bandCounts.reduce(into: [:]) { $0[$1.key.name] = $1.value }
    }
}
