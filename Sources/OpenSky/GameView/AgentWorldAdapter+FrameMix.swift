// The `soundMix` and `treeWind` parts of `state frame` (docs/engine/sound-mix.md,
// docs/rendering/trees.md).

import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorld

extension AgentWorldAdapter {
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

    func treeWindState() -> AgentJSON {
        guard let session = game.gameSession else { return .null }
        let wind = session.renderer.frameInput.wind
        return [
            "direction": .array([.init(wind.direction.x), .init(wind.direction.y)]),
            "speed": .init(min(max(wind.speed, 0), 1)),
            "leafFadeDistance": .init(TreeWindPolicy.leafFadeDistance)
        ]
    }
}
