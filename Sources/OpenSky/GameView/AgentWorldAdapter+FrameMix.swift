// The `soundMix`, `treeWind`, and `waterFlow` parts of `state frame` (docs/engine/sound-mix.md,
// docs/rendering/trees.md, docs/rendering/water.md), the skin decals of `state actors`, and the
// low-health cues of `state player` (docs/rendering/image-space.md#low-health).

import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyEffects
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySessionInterface
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
