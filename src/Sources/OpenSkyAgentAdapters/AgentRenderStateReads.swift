import Foundation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLoading
import OpenSkyMenusInterface
import OpenSkyObjectAnimation
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySaveInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// The lighting, post-effect, weather, sound, and effect readouts of `AgentRenderAdapter`.
struct AgentRenderStateReads {
    let game: any AgentRenderHost

    func lightingState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let renderer = session.renderer
        let grade = session.imageSpace.current
        var result: [String: AgentJSON] = [
            "eyeLuminance": renderer.eyeAdaptation.adaptedLuminance.map(AgentJSON.init) ?? .null,
            "exposure": .init(renderer.eyeAdaptation.exposure),
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
        let live = game.combat.liveProjectiles
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

    func soundMixState() -> AgentJSON {
        guard let mix = game.gameSession?.worldAudio?.soundMix else { return .null }
        let inputs = mix.inputs
        var roles: [String: AgentJSON] = [:]
        for role in SoundCategoryRole.allCases {
            guard let category = mix.roles[role] else { continue }
            let level = mix.level(of: category)
            roles[role.rawValue] = [
                "category": .string(mix.categories[category.rawValue]?.editorID ?? "\(category)"),
                "gain": .init(level.gain),
                "paused": .bool(level.paused)
            ]
        }
        return [
            "menuMode": .bool(inputs.menuMode),
            "loading": .bool(inputs.loading),
            "dialogue": .bool(inputs.dialogue),
            "submerged": .bool(inputs.submerged),
            "statsMenu": .bool(inputs.statsMenu),
            "menuLevel": .init(mix.menuLevel),
            "dialogueLevel": .init(mix.dialogueLevel),
            "musicLevel": .init(mix.musicLevel),
            "roles": .object(roles)
        ]
    }

    /// The bone each skin decal on `actor` rides, or `feet` for one without a bone.
    func skinDecalBones(of actor: ReferenceKey) -> [String] {
        let skin = game.effects.skinDecals
        return skin.owners.filter { $0.value == actor }.keys.sorted()
            .map { skin.bones[$0] ?? "feet" }
    }

    func treeWindState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let wind = session.renderer.frameInput.wind
        return [
            "direction": .array([.init(wind.direction.x), .init(wind.direction.y)]),
            "speed": .init(min(max(wind.speed, 0), 1)),
            "leafFadeDistance": .init(TreeWindPolicy.leafFadeDistance)
        ]
    }

    func waterFlowState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let maps = session.renderer.waterFlowMaps()
        return [
            "planes": .init(session.renderer.scene.water.count),
            "flowMaps": .array(maps.map { .string($0.path) }),
            "loaded": .init(maps.filter(\.loaded).count)
        ]
    }

    /// The snow look the weather's `SPGD` asks for, and the one drawn now.
    func precipitationState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let volume = session.renderer.precipitation
        let path = { (look: PrecipitationLook?) in look.map { AgentJSON.string($0.texturePath) } }
        return [
            "source": volume.tuning.source.map(AgentJSON.string) ?? .null,
            "snowTexture": path(volume.tuning.snowLook) ?? .null,
            "drawnSnowTexture": path(volume.snowLook) ?? .null,
            "snowCells": .init(volume.snowLook.map { $0.columns * $0.rows } ?? 1)
        ]
    }

    func healthCueState() -> AgentJSON {
        let cues = game.effects.healthCues
        return [
            "heartbeat": cues.heartbeat.map { .string("\($0)") } ?? .null,
            "pulseEnabled": .bool(cues.pulseEnabled),
            "pulsing": .bool(cues.pulsing),
            "pulseCount": .init(cues.pulseCount),
            "lastPulseStrength": cues.lastPulseStrength.map { .init($0) } ?? .null,
            "modifierFound": .bool(game.effects.records.lowHealthModifier != nil)
        ]
    }
}
