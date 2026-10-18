// The effects a Papyrus script plays: `VisualEffect.Play`, `EffectShader.Play`, and the
// `ImageSpaceModifier` natives. The rules live in `EffectsCoordinator`.

import Foundation
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkyWorld

extension EffectsWorldAdapter: PapyrusEffectPresenting {
    func playEffect(_ effect: ReferenceKey, on target: ReferenceKey, duration: Float?) -> Bool {
        effects.attach(effect, to: .actor(target), cause: .script, duration: duration) != nil
    }

    func stopEffect(_ effect: ReferenceKey, on target: ReferenceKey) -> Bool {
        effects.detach(effect, from: .actor(target)) > 0
    }

    func applyImageSpaceModifier(_ modifier: ReferenceKey, strength: Float, held: Bool) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        return effects.startModifier(
            modifier, strength: strength, looping: held, on: &gameSession.imageSpace
        )
    }

    func removeImageSpaceModifier(_ modifier: ReferenceKey) {
        guard let gameSession = game.gameSession else { return }
        effects.stopModifier(modifier, on: &gameSession.imageSpace)
    }
}
