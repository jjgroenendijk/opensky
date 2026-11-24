// The HUD movie's own timeline, where a hint or notice fades out after the engine hides
// it (docs/rendering/hud.md#timing), and the key art its hints ask the engine for.

import OpenSkyFormatsSWF
import OpenSkyRendering

extension HUDCoordinator {
    /// The game moves the HUD movie by at most 1/24 s in one update.
    static let maximumAdvance = 1.0 / 24

    /// Steps the movie by real time at its own frame rate, also while a menu pauses the
    /// game, so a fade takes as long as in the game whatever the display rate.
    public func tick(now: Double) {
        guard isLoaded else { return }
        let due = framePacer.ticks(
            at: now,
            frameRate: frameRate,
            maximumInterval: Self.maximumAdvance
        )
        guard due > 0 else { return }
        callMovie { runtime in
            for _ in 0 ..< due {
                runtime.advance()
            }
        }
    }
}

extension HUDCoordinator {
    func registerButtonArt(runtime: SWFMovieRuntime) {
        MenuMovieButtonArt.register(runtime: runtime) { [weak self] event in
            let gamepad = (self?.renderer?.swfGamepadCount ?? 0) > 0
            return self?.buttonName?(event, gamepad)
        }
    }
}
