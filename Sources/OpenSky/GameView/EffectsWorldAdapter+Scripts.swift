// The effects a Papyrus script plays: `VisualEffect.Play`, `EffectShader.Play`, and the
// `ImageSpaceModifier` natives. The rules live in `EffectsCoordinator`.

import Foundation
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld

extension EffectsWorldAdapter: PapyrusEffectPresenting {
    func playEffect(
        _ effect: ReferenceKey, on target: ReferenceKey, duration: Float?, facing: ReferenceKey?
    ) -> Bool {
        effects.attach(
            effect, to: .actor(target), cause: .script, duration: duration, facing: facing
        ) != nil
    }

    func stopEffect(_ effect: ReferenceKey, on target: ReferenceKey) -> Bool {
        effects.detach(effect, from: .actor(target)) > 0
    }

    func applyImageSpaceModifier(
        _ modifier: ReferenceKey, strength: Float, held: Bool, fadeSeconds: Float
    ) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        return effects.startModifier(
            modifier, strength: strength, looping: held, fadeIn: fadeSeconds,
            on: &gameSession.imageSpace
        )
    }

    func removeImageSpaceModifier(_ modifier: ReferenceKey, fadeSeconds: Float) {
        guard let gameSession = game.gameSession else { return }
        effects.stopModifier(modifier, fadeOut: fadeSeconds, on: &gameSession.imageSpace)
    }
}
