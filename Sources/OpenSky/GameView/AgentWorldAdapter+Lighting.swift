// The `lighting` part of `state frame`: the weather colours the frame shades with and the
// image space grade on top, to trace a tone difference to its input.

import Foundation
import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorld

extension AgentWorldAdapter {
    func lightingState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let renderer = session.renderer
        let grade = session.imageSpace.current
        var result: [String: AgentJSON] = [
            "eyeLuminance": renderer.eyeAdaptation.adaptedLuminance.map(AgentJSON.init) ?? .null,
            "exposure": .init(renderer.eyeAdaptation
                .exposure(strength: grade.hdr.eyeAdaptStrength)),
            "imageSpace": [
                "eyeAdaptSpeed": .init(grade.hdr.eyeAdaptSpeed),
                "eyeAdaptStrength": .init(grade.hdr.eyeAdaptStrength),
                "white": .init(grade.hdr.white),
                "saturation": .init(grade.saturation),
                "brightness": .init(grade.brightness),
                "contrast": .init(grade.contrast),
                "tint": .array([grade.tint.x, grade.tint.y, grade.tint.z, grade.tint.w]
                    .map(AgentJSON.init))
            ]
        ]
        result["weather"] = session.currentResolvedWeather.map(weatherLightingState) ?? .null
        return .object(result)
    }

    private func weatherLightingState(_ weather: ResolvedWeather) -> AgentJSON {
        let ambient = weather.directionalAmbient
        return [
            "sunlight": .init(weather.sunlightColor),
            "ambient": .init(weather.ambientColor),
            "directionalAmbient": [
                "positiveX": .init(ambient.positiveX), "negativeX": .init(ambient.negativeX),
                "positiveY": .init(ambient.positiveY), "negativeY": .init(ambient.negativeY),
                "positiveZ": .init(ambient.positiveZ), "negativeZ": .init(ambient.negativeZ)
            ],
            "skyUpper": .init(weather.skyUpper),
            "skyLower": .init(weather.skyLower),
            "horizon": .init(weather.horizon),
            "fog": [
                "nearColour": .init(weather.fogNearColor), "farColour": .init(weather.fogFarColor),
                "near": .init(weather.fogNearDistance), "far": .init(weather.fogFarDistance),
                "power": .init(weather.fogPower), "maximum": .init(weather.fogMaximum)
            ]
        ]
    }
}
