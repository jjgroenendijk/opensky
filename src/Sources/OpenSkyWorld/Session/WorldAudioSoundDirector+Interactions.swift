// Door and activator sounds: the activation one-shot, and the loop and close sound of a
// door animation.

import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface
import simd

extension WorldAudioInteractionSounds {
    /// CellStreamer.onInteraction subscriber. Plays the activator's activation
    /// sound (DOOR.SNAM, ACTI.VNAM, CONT.SNAM) at the placed position.
    func handleInteraction(_ event: InteractionEvent) {
        guard
            director.sfxEnabled, director.engine.isRunning,
            let sounds = event.target.interaction.sounds,
            let activationID = sounds.activation
        else { return }
        director.playback.playResolved(
            id: activationID,
            at: event.target.interaction.position,
            kind: "SFX"
        )
    }

    /// Door-animation lifecycle subscriber. Movement starts the authored loop;
    /// close and cancellation both retire it, while only close plays the
    /// authored one-shot. The same event also supports a future container
    /// animation because DOOR.ANAM and CONT.QNAM share `sounds.close`.
    func handleInteractionAnimation(_ event: InteractionAnimationEvent) {
        let interaction = event.interaction
        switch event.phase {
        case .motionStarted:
            retireInteractionLoop(reference: interaction.reference)
            guard
                director.sfxEnabled,
                director.engine.isRunning,
                let loopID = interaction.sounds?.loop
            else { return }
            director.nextLoopToken += 1
            let token = director.nextLoopToken
            let reference = interaction.reference
            director.interactionLoopTokens[reference] = token
            director.playback.playResolved(
                id: loopID, at: interaction.position, kind: "interaction loop", loops: true
            ) { [weak director] sourceID in
                guard let director, director.interactionLoopTokens[reference] == token else {
                    return false
                }
                director.interactionLoopSourceIDs[reference] = sourceID
                return true
            }
        case .closed:
            retireInteractionLoop(reference: interaction.reference)
            guard
                director.sfxEnabled,
                director.engine.isRunning,
                let closeID = interaction.sounds?.close
            else { return }
            director.playback.playResolved(
                id: closeID,
                at: interaction.position,
                kind: "interaction close"
            )
        case .cancelled:
            retireInteractionLoop(reference: interaction.reference)
        }
    }

    private func retireInteractionLoop(reference: FormID) {
        director.interactionLoopTokens[reference] = nil
        guard let sourceID = director.interactionLoopSourceIDs.removeValue(forKey: reference) else {
            return
        }
        director.engine.stopSource(id: sourceID)
    }
}
