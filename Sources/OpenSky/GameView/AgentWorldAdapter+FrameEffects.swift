// The `postEffects` and `projectileVisuals` parts of `state frame`: the screen effects,
// and what flying projectiles and short flashes draw (docs/rendering/post-effects.md,
// docs/engine/spell-delivery.md#what-a-projectile-shows).

import Foundation
import OpenSkyAgentControl
import OpenSkyCombat
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorld

extension AgentWorldAdapter {
    func postEffectState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let settings = session.renderer.postEffects
        let field = session.imageSpace.current
        let look = session.renderer.volumetricLight
        return [
            "ambientOcclusion": .bool(settings.ambientOcclusion),
            "characterLight": [
                "enabled": .bool(session.renderer.characterLightEnabled),
                "strength": .init(session.renderer.characterLightUniform.z)
            ],
            "actorCameraFade": .object(session.renderer.actorCameraFadeOuts.reduce(into: [:]) {
                unsafe $0[String(format: "%08X", $1.key)] = .init($1.value)
            }),
            "fxaa": .bool(settings.fxaa),
            "indirectLight": .bool(settings.indirectLight),
            "lensFlare": .bool(settings.lensFlare),
            "depthOfField": [
                "enabled": .bool(settings.depthOfField),
                "strength": .init(field.depthOfField.x),
                "distance": .init(field.depthOfField.y),
                "range": .init(field.depthOfField.z),
                "blurRadius": .init(field.depthOfFieldBlurRadius),
                "skySharp": .bool(field.depthOfFieldKeepsSkySharp),
                "sides": .string("\(field.depthOfFieldSides)"),
                "usesTarget": .bool(field.depthOfFieldUsesTarget),
                "centreWeight": .init(session.renderer.depthOfFieldFocus.centreWeight)
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

    func projectileVisualState() -> AgentJSON {
        let live = game.combat.archery?.projectiles.live ?? []
        return [
            "flying": .array(live.map { projectile in
                [
                    "id": .init(projectile.id),
                    "model": projectile.profile.visuals.model.map(AgentJSON.string) ?? .null,
                    "lit": .bool(projectile.profile.visuals.light != nil),
                    "position": .init(projectile.position)
                ]
            }),
            "flashLights": .array(game.effects.flashLights.map { flash in
                ["light": .string(flash.light.description), "strength": .init(flash.strength)]
            }),
            "transientLights": .init(game.gameSession?.renderer.transientPointLights.count ?? 0)
        ]
    }
}
