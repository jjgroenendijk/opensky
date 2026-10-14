// `VisualEffect`, `EffectShader`, and `ImageSpaceModifier` natives
// (<https://ck.uesp.net/wiki/VisualEffect_Script>, <https://ck.uesp.net/wiki/EffectShader_Script>,
// <https://ck.uesp.net/wiki/ImageSpaceModifier_Script>). They draw through the session's
// `PapyrusEffectPresenting` port; a headless session draws nothing and answers at once.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// The `.player` script-state link that names the modifier `ApplyCrossFade` holds.
    static let crossFadeModifierName = "crossFadeModifier"

    public static func installEffects(into registry: inout PapyrusNativeRegistry) {
        // `Play(ObjectReference akObject, float afTime = -1.0, ...)`: a negative time
        // plays until `Stop`.
        for script in ["VisualEffect", "EffectShader"] {
            effect(script, "Play", into: &registry) { call, presenter, effect, target in
                let time = float(call, at: 1) ?? -1
                let duration: Float? = time.isFinite && time >= 0 ? time : nil
                presenter?.playEffect(effect, on: target, duration: duration)
                return .returned(.none)
            }
            effect(script, "Stop", into: &registry) { _, presenter, effect, target in
                presenter?.stopEffect(effect, on: target)
                return .returned(.none)
            }
        }
        installImageSpaceModifiers(into: &registry)
    }

    /// `Apply(float afStrength = 1.0)`, `ApplyCrossFade(float afFadeDuration = 1.0)`,
    /// `PopTo(ImageSpaceModifier, float afStrength = 1.0)`, `Remove()`, and the global
    /// `RemoveCrossFade(float afFadeDuration = 1.0)`. Fade times are not modelled.
    private static func installImageSpaceModifiers(into registry: inout PapyrusNativeRegistry) {
        scriptState("ImageSpaceModifier", "Apply", into: &registry) { call, bridge, key in
            let strength = float(call, at: 0) ?? 1
            bridge.effectPresenter?.applyImageSpaceModifier(key, strength: strength, held: false)
            return .returned(.none)
        }
        scriptState("ImageSpaceModifier", "Remove", into: &registry) { _, bridge, key in
            bridge.effectPresenter?.removeImageSpaceModifier(key)
            return .returned(.none)
        }
        scriptState("ImageSpaceModifier", "PopTo", into: &registry) { call, bridge, key in
            guard let next = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)) else {
                return failure(call, "PopTo needs an image space modifier")
            }
            bridge.effectPresenter?.removeImageSpaceModifier(key)
            let strength = float(call, at: 1) ?? 1
            bridge.effectPresenter?.applyImageSpaceModifier(next, strength: strength, held: false)
            return .returned(.none)
        }
        scriptState("ImageSpaceModifier", "ApplyCrossFade", into: &registry) { _, bridge, key in
            removeCrossFade(bridge)
            bridge.effectPresenter?.applyImageSpaceModifier(key, strength: 1, held: true)
            bridge.updateScriptedState(of: .player) { $0.setForm(crossFadeModifierName, key) }
            return .returned(.none)
        }
        registry.register(PapyrusNativeFunction(
            scriptName: "ImageSpaceModifier", functionName: "RemoveCrossFade"
        ) { call, context in
            guard let bridge = context.world as? PapyrusWorldStateBridge else {
                return needsWorld(call)
            }
            removeCrossFade(bridge)
            return .returned(.none)
        })
    }

    private static func removeCrossFade(_ bridge: PapyrusWorldStateBridge) {
        guard let held = bridge.scriptedState(of: .player).form(crossFadeModifierName) else {
            return
        }
        bridge.effectPresenter?.removeImageSpaceModifier(held)
        bridge.updateScriptedState(of: .player) { $0.setForm(crossFadeModifierName, nil) }
    }

    /// Registers a native whose receiver is the effect form and whose first argument
    /// is the reference it plays on.
    private static func effect(
        _ script: String, _ name: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, (any PapyrusEffectPresenting)?, ReferenceKey, ReferenceKey
        ) -> PapyrusNativeResult
    ) {
        scriptState(script, name, into: &registry) { call, bridge, effect in
            guard let target = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)) else {
                return failure(call, "\(name) needs a reference to play on")
            }
            return body(call, bridge.effectPresenter, effect, target.namingPlayer)
        }
    }
}
