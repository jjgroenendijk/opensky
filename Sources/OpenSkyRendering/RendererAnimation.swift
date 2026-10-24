// Per-frame actor animation clock + measured palette refresh.

import Foundation
import OpenSkyRenderCore

extension Renderer {
    public func updateAnimations(deltaTime: Float) {
        animationTime += max(deltaTime, 0)
        let started = DispatchTime.now().uptimeNanoseconds
        let sceneBones = if actorAnimationsEnabled {
            scene.updateAnimations(at: animationTime)
        } else {
            scene.resetAnimationsToBindPose()
        }
        // The simulation steps the player's animation; this only publishes the pose and
        // honours the same A/B toggle (PlayerAnimationPlayback.swift).
        lastAnimationUpdatedBoneCount = sceneBones
            + (frameInput.rigs.body?.publishAnimation(enabled: actorAnimationsEnabled) ?? 0)
            + (frameInput.rigs.arms?.publishAnimation(enabled: actorAnimationsEnabled) ?? 0)
        lastAnimationUpdateMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    @discardableResult
    public func updateAnimationsFromWallClock() -> Float {
        // Returned delta also drives particles + precipitation this frame, so a
        // paused (zero) delta freezes all three together.
        let delta = animationClock
            .advance(to: wallClock.now, paused: frameInput.isPaused) * frameInput.timeScale
        updateAnimations(deltaTime: delta)
        return delta
    }

    public func updateParticles(deltaTime: Float) {
        guard particlesEnabled, !particlesFrozen else { return }
        for playback in scene.particles + effects.particles {
            playback.advance(
                deltaTime: deltaTime,
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
