// Per-frame actor animation clock + measured palette refresh.

import QuartzCore

extension Renderer {
    func updateAnimations(deltaTime: Float) {
        animationTime += max(deltaTime, 0)
        let started = DispatchTime.now().uptimeNanoseconds
        lastAnimationUpdatedBoneCount = if actorAnimationsEnabled {
            scene.updateAnimations(at: animationTime)
        } else {
            scene.resetAnimationsToBindPose()
        }
        lastAnimationUpdateMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    @discardableResult
    func updateAnimationsFromWallClock() -> Float {
        // Returned delta also drives particles + precipitation this frame, so a
        // paused (zero) delta freezes all three together.
        let delta = animationClock.advance(to: CACurrentMediaTime(), paused: worldSimPaused)
        updateAnimations(deltaTime: delta)
        return delta
    }

    func updateParticles(deltaTime: Float) {
        guard particlesEnabled, !particlesFrozen else { return }
        for playback in scene.particles {
            playback.advance(
                deltaTime: deltaTime,
                wind: currentWind,
                emissionScale: particleEmissionScale
            )
        }
    }

    func seekParticles(to time: Float) {
        guard particlesEnabled else { return }
        for playback in scene.particles {
            playback.seek(
                to: time,
                wind: currentWind,
                emissionScale: particleEmissionScale
            )
        }
    }
}
