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
        let now = CACurrentMediaTime()
        let delta = lastAnimationWallTime.map { Float(min(now - $0, 0.1)) } ?? 0
        lastAnimationWallTime = now
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
