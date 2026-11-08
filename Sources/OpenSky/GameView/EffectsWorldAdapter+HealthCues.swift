// App side of the low-health cues: reads the player's health share, lets the effects
// coordinator start the pulse, and plays the heartbeat it asks for.

import OpenSkyActors
import OpenSkyEffects
import OpenSkyGameData
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface

extension EffectsWorldAdapter {
    /// A load stops the heartbeat at once and forgets the last health, as the game does.
    func resetHealthCues() {
        game.audio.soundDirector?.stopScriptSound(heartbeatSound)
        heartbeatSound = 0
        game.effects.resetHealthCues()
    }

    /// A new game fades the heartbeat out, as the game does on a start.
    func fadeOutHealthCues() {
        game.audio.soundDirector?.fadeOutScriptSound(
            heartbeatSound, seconds: PlayerHealthCues.heartbeatFadeSeconds
        )
        heartbeatSound = 0
        game.effects.resetHealthCues()
    }

    func stepHealthCues(_ seconds: Float, gameSession: GameSession) {
        guard let values = game.actorValues.runtime else { return }
        let director = game.audio.soundDirector
        let share = PlayerHealthCues.share(
            current: values.current(of: .player).health,
            maximum: values.permanentMaximum(of: .health, for: .player)
        )
        let playing = heartbeatSound != 0 && director?.isScriptSoundPlaying(heartbeatSound) == true
        let change = game.effects.stepHealthCues(
            share: share, seconds: seconds, heartbeatPlaying: playing,
            imageSpace: &gameSession.imageSpace
        )
        guard let change, let director else { return }
        switch change {
        case let .start(heartbeat):
            director.stopScriptSound(heartbeatSound)
            heartbeatSound = 0
            guard let sound = game.effects.heartbeatSound(heartbeat) else { return }
            heartbeatSound = director.playScriptSound(
                formID: sound, at: cameraPosition ?? .zero
            )
        case .fadeOut:
            director.fadeOutScriptSound(
                heartbeatSound, seconds: PlayerHealthCues.heartbeatFadeSeconds
            )
            heartbeatSound = 0
        }
    }
}
