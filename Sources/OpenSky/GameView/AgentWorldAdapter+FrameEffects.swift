// The `postEffects` part of `state frame`: which screen effects are on, the depth of
// field the image space asks for, and the weather's volumetric light
// (docs/rendering/post-effects.md).

import Foundation
import OpenSkyAgentControl
import OpenSkyRenderCore

extension AgentWorldAdapter {
    func postEffectState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let settings = session.renderer.postEffects
        let field = session.imageSpace.current
        let look = session.renderer.volumetricLight
        return [
            "ambientOcclusion": .bool(settings.ambientOcclusion),
            "fxaa": .bool(settings.fxaa),
            "lensFlare": .bool(settings.lensFlare),
            "depthOfField": [
                "enabled": .bool(settings.depthOfField),
                "strength": .init(field.depthOfField.x),
                "distance": .init(field.depthOfField.y),
                "range": .init(field.depthOfField.z),
                "blurRadius": .init(field.depthOfFieldBlurRadius),
                "skySharp": .bool(field.depthOfFieldKeepsSkySharp),
                "sides": .string("\(field.depthOfFieldSides)")
            ],
            "volumetricLight": [
                "enabled": .bool(settings.volumetricLight),
                "steps": .init(settings.volumetricSteps),
                "intensity": .init(look.intensity),
                "customColor": .init(look.customColorContribution),
                "density": .init(look.densityContribution),
                "phaseContribution": .init(look.phaseFunctionContribution),
                "scattering": .init(look.phaseFunctionScattering),
                "samplingRange": .init(look.samplingRangeFactor)
            ]
        ]
    }
}
