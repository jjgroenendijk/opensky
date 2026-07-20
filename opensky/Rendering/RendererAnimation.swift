// Per-frame actor animation clock + measured palette refresh.

import QuartzCore

extension Renderer {
    func updateAnimations(deltaTime: Float) {
        animationTime += max(deltaTime, 0)
        let started = DispatchTime.now().uptimeNanoseconds
        _ = scene.updateAnimations(at: animationTime)
        lastAnimationUpdateMS =
            Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
    }

    func updateAnimationsFromWallClock() {
        let now = CACurrentMediaTime()
        let delta = lastAnimationWallTime.map { Float(min(now - $0, 0.1)) } ?? 0
        lastAnimationWallTime = now
        updateAnimations(deltaTime: delta)
    }
}
